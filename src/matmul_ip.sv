// =============================================================================
//  matmul_ip.sv  —  General-purpose matrix multiply engine
//
//  Tính:  C = A · Bᵀ
//    A : [N_ROWS × D_MODEL]   — broadcast từng phần tử vào (caller đọc RAM)
//    B : [N_COLS × D_MODEL]   — preload vào weight local của PE
//    C : [N_ROWS × N_COLS]    — kết quả, xuất N_PE cột mỗi lần
//
//  ┌─ Trường hợp ①: Q·Kᵀ  (3×64 × 64×3) ─────────────────────────────────┐
//  │  N_ROWS=3  N_COLS=3  D_MODEL=64  N_PE=3                               │
//  │  N_TILES=1 → preload K 1 lần, compute 3 hàng × 64 cycle = 192 cy     │
//  │  Backward compat hoàn toàn với linear.sv (không sửa gì)               │
//  └────────────────────────────────────────────────────────────────────────┘
//
//  ┌─ Trường hợp ②: 64×64 × 64×64 ─────────────────────────────────────────┐
//  │  N_ROWS=64  N_COLS=64  D_MODEL=64  N_PE=64  (tối đa song song)        │
//  │  N_TILES=1 → preload B 1 lần (4096 cy), compute 64 hàng × 64 cy      │
//  │  Total ≈ 8192 cycles                                                   │
//  │  N_PE=32 → N_TILES=2, caller quản lý tile loop                        │
//  └────────────────────────────────────────────────────────────────────────┘
//
//  Parameter N_PE — chọn theo mục tiêu:
//    N_PE = N_COLS : tối đa song song, 1 lần preload B
//    N_PE < N_COLS : ít tài nguyên hơn, caller quản lý tile loop
//
//  Tiling (khi N_PE < N_COLS):
//    Caller thực hiện vòng lặp sau:
//      for tile = 0 .. N_TILES-1:
//        assert i_col_base = tile * N_PE
//        Preload B[tile*N_PE .. (tile+1)*N_PE - 1][:] vào PE[0..N_PE-1]
//        for i = 0 .. N_ROWS-1:
//          Drive i_data_valid=1, i_a_data=A[i][k], k=0..D_MODEL-1
//          Nhận o_result_valid pulse
//          C[i][tile*N_PE .. tile*N_PE + N_PE - 1] = o_result[0..N_PE-1]
//
//  Ports mới (so với phiên bản trước):
//    i_col_base       : tile column offset, đặt 0 khi N_TILES=1
//    o_result_col_base: echo i_col_base delay 1 cycle (sync với o_result_valid)
//    Cả hai có thể bỏ qua khi N_PE = N_COLS.
// =============================================================================


// -----------------------------------------------------------------------------
//  pe_unit — Processing Element (không thay đổi so với phiên bản trước)
//
//  Lưu một hàng B[j][0..D_MODEL-1] trong weight[] (FF / LUT-RAM).
//  MAC:    acc += A[i][k] * weight[k]
//  Round:  Round-to-Nearest-Even → DATA_WIDTH bit
// -----------------------------------------------------------------------------
module pe_unit #(
    parameter int D_MODEL    = 64,
    parameter int DATA_WIDTH = 16
)(
    input  logic i_clk,
    input  logic i_reset_n,

    input  logic                          i_preload_en,
    input  logic [$clog2(D_MODEL)-1:0]   i_preload_k,
    input  logic signed [DATA_WIDTH-1:0] i_preload_data,

    input  logic                          i_compute_en,
    input  logic                          i_acc_clear,
    input  logic [$clog2(D_MODEL)-1:0]   i_k_index,
    input  logic signed [DATA_WIDTH-1:0] i_broadcast_x,

    output logic signed [DATA_WIDTH-1:0] o_result
);
    localparam int ACC_WIDTH = DATA_WIDTH * 2 + $clog2(D_MODEL);
    localparam int FRAC_BITS = DATA_WIDTH / 2;

    logic signed [DATA_WIDTH-1:0] weight [0:D_MODEL-1];
    logic signed [ACC_WIDTH-1:0]  acc;

    always_ff @(posedge i_clk or negedge i_reset_n) begin
        if (!i_reset_n) begin
        end else if (i_preload_en) begin
            weight[i_preload_k] <= i_preload_data;
        end
    end

    always_ff @(posedge i_clk or negedge i_reset_n) begin
        if (!i_reset_n) begin
            acc <= '0;
        end else if (i_compute_en) begin
            if (i_acc_clear)
                acc <= ACC_WIDTH'($signed(i_broadcast_x) * $signed(weight[i_k_index]));
            else
                acc <= acc + ACC_WIDTH'($signed(i_broadcast_x) * $signed(weight[i_k_index]));
        end
    end

    logic round_up;
    assign round_up = acc[FRAC_BITS-1] & (|acc[FRAC_BITS-2:0] | acc[FRAC_BITS]);
    assign o_result = acc[FRAC_BITS + DATA_WIDTH - 1 : FRAC_BITS]
                    + DATA_WIDTH'({(DATA_WIDTH-1)'(0), round_up});

endmodule


// =============================================================================
//  matmul_ip — Top module
// =============================================================================
module matmul_ip #(
    // ── NGƯỜI DÙNG ĐIỀN ──────────────────────────────────────────────────────

    parameter int N_COLS     = 3,    // số cột B    (SEQ_LEN cho Q·Kᵀ; 64 cho 64×64)
    parameter int D_MODEL    = 64,   // chiều k
    parameter int N_PE       = 3,    // số PE chạy song song
    //             Set N_PE = N_COLS để tối đa hoá song song (không cần tile loop)
    //             Giảm N_PE để tiết kiệm tài nguyên, cần caller quản lý tile loop
    parameter int DATA_WIDTH = 16
)(
    input  logic i_clk,
    input  logic i_reset_n,

    // ── PRELOAD: caller truyền B[j_local][k] vào PE[j_local] ─────────────────
    // j_local = index PE trong tile hiện tại (0 .. N_PE-1)
    input  logic                            i_preload_en,
    input  logic [$clog2(N_PE>1?N_PE:2)-1:0]       i_preload_j,
    input  logic [$clog2(D_MODEL)-1:0]     i_preload_k,
    input  logic signed [DATA_WIDTH-1:0]   i_preload_data,

    // ── COMPUTE: caller broadcast A[i][k] ────────────────────────────────────
    input  logic                            i_data_valid,
    input  logic                            i_acc_clear,
    input  logic [$clog2(D_MODEL)-1:0]     i_k_index,
    input  logic signed [DATA_WIDTH-1:0]   i_a_data,

    // ── TILE OFFSET ───────────────────────────────────────────────────────────
    // Đặt 0 khi N_PE = N_COLS (không cần tiling)
    input  logic [$clog2(N_COLS>1?N_COLS:2)-1:0]   i_col_base,

    // ── OUTPUT ────────────────────────────────────────────────────────────────
    output logic                                        o_result_valid,
    output logic signed [N_PE-1:0][DATA_WIDTH-1:0]     o_result,
    output logic [$clog2(N_COLS>1?N_COLS:2)-1:0]   o_result_col_base
);

    // =========================================================================
    // Derived localparams (dùng nội bộ, không dùng trong port)
    // =========================================================================
    localparam int N_TILES = (N_COLS + N_PE - 1) / N_PE;
    localparam int J_W = (N_PE   > 1) ? $clog2(N_PE)   : 1;
    localparam int C_W = (N_COLS > 1) ? $clog2(N_COLS) : 1;
    // =========================================================================
    // Compile-time assertions
    // =========================================================================
    // synthesis translate_off
    initial begin
        assert (N_PE >= 1 && N_PE <= N_COLS) else
            $fatal(1, "[matmul_ip] N_PE=%0d phải nằm trong [1, N_COLS=%0d]", N_PE, N_COLS);
        assert (D_MODEL >= 2) else
            $fatal(1, "[matmul_ip] D_MODEL=%0d phải >= 2", D_MODEL);
        if (N_COLS % N_PE != 0)
            $warning("[matmul_ip] N_COLS=%0d không chia hết N_PE=%0d → %0d PE cuối bị disable",
                     N_COLS, N_PE, N_PE - (N_COLS % N_PE));
    end
    // synthesis translate_on

    // =========================================================================
    // Generate N_PE instance pe_unit
    //
    //   PE[p] tính cột  j_abs = i_col_base + p  của ma trận C.
    //   pe_active[p]:  tắt PE khi j_abs >= N_COLS (xảy ra khi N_COLS % N_PE != 0)
    //   So sánh dùng int để tránh phụ thuộc bit-width của i_col_base.
    // =========================================================================
    genvar gp;
    generate
        for (gp = 0; gp < N_PE; gp++) begin : gen_pe

            // Chọn PE nhận preload
            logic pe_preload_en;
            assign pe_preload_en = i_preload_en & (i_preload_j == J_W'(gp));

            // Disable PE khi j_abs vượt N_COLS (tile padding)
            logic pe_active;
            assign pe_active = 1'b1;

            pe_unit #(
                .D_MODEL   (D_MODEL),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_pe (
                .i_clk         (i_clk),
                .i_reset_n     (i_reset_n),

                .i_preload_en  (pe_preload_en & pe_active),
                .i_preload_k   (i_preload_k),
                .i_preload_data(i_preload_data),

                .i_compute_en  (i_data_valid & pe_active),
                .i_acc_clear   (i_acc_clear),
                .i_k_index     (i_k_index),
                .i_broadcast_x (i_a_data),

                .o_result      (o_result[gp])
            );

        end
    endgenerate

    // =========================================================================
    // o_result_valid: pulse 1 cycle sau i_data_valid fall
    //
    //   PE là FF: kết quả k cuối (D_MODEL-1) ổn định 1 cycle sau i_data_valid fall.
    //   → delay i_data_valid 1 cycle → pulse khi (valid_d1 & !i_data_valid).
    // =========================================================================
    logic valid_d1;

    always_ff @(posedge i_clk or negedge i_reset_n) begin
        if (!i_reset_n)
            valid_d1 <= 1'b0;
        else
            valid_d1 <= i_data_valid;
    end

    assign o_result_valid = valid_d1 & ~i_data_valid;

    // =========================================================================
    // o_result_col_base: delay 1 cycle để đồng bộ với o_result_valid
    // =========================================================================
    logic [C_W-1:0] col_base_d1;

    always_ff @(posedge i_clk or negedge i_reset_n) begin
        if (!i_reset_n)
            col_base_d1 <= '0;
        else
            col_base_d1 <= i_col_base;
    end

    assign o_result_col_base = col_base_d1;

endmodule