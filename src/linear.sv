`timescale 1ns / 1ps

module linear #(
    parameter int D_MODEL    = 64,
    parameter int SEQ_LEN    = 64,
    parameter int DATA_WIDTH = 16,
    parameter int N_PE = 64,
    parameter int D_HEAD = 64

)(
    input  logic i_clock,
    input  logic i_reset_n,

    input  logic i_start_attn_score,
    output logic o_attn_score_done,

    input  logic [31:0] i_dina_q,
    input logic [31-1:0] i_addra_q,
    input  logic        i_wea_q,

    input  logic [31:0] i_dina_k,
    input logic [31-1:0] i_addra_k,
    input  logic        i_wea_k,

    input  logic [31:0] i_dina_v,
    input logic [31:0] i_addra_v,
    input  logic        i_wea_v,

    input  logic [31:0] i_sram_addrb,
    output logic signed [31:0] o_sram_doutb,

    output logic        o_s_ram_we,
    output logic [31:0] o_s_ram_addr,
    output logic signed [31:0] o_s_ram_data,
    output logic o_busy
);

    localparam int QK_DEPTH     = SEQ_LEN * D_MODEL;
    localparam int S_DEPTH      = SEQ_LEN * SEQ_LEN;
    localparam int K_W          = $clog2(D_MODEL);
    localparam int ROW_W        = $clog2(SEQ_LEN);
    localparam int SQRT_SHIFT   = $clog2(D_MODEL) / 2;
    localparam int BRAM_LATENCY = 2;

    logic [31:0] q_addrb, k_addrb;
    logic signed [31:0]   q_doutb, k_doutb;

    logic matmul_preload_en;
    logic [ROW_W-1:0] matmul_preload_j;
    logic [K_W-1:0]   matmul_preload_k;
    logic signed [DATA_WIDTH-1:0] matmul_preload_data;

    logic matmul_data_valid;
    logic matmul_acc_clear;
    logic [K_W-1:0] matmul_k_index;
    logic signed [DATA_WIDTH-1:0] matmul_a_data;

    logic matmul_result_valid;
    logic signed [SEQ_LEN-1:0][DATA_WIDTH-1:0] matmul_result;

    logic s_we;
    logic [31:0] s_addr;
    logic signed [31:0] s_data;

    logic signed [31:0] scaled_store_data;

    logic                  s_ram_wea;
    logic [31:0] s_ram_addra;
    logic signed [31:0]    s_ram_dina;
    logic signed [SEQ_LEN-1:0][DATA_WIDTH-1:0] result_latch;

    logic [ROW_W-1:0] row_i;
    logic [ROW_W-1:0] row_j;
    logic [ROW_W-1:0] store_j;
    logic [K_W-1:0]   col_k;
    logic [2:0]       drain_cnt;

    logic [ROW_W-1:0] j_pipe [0:BRAM_LATENCY-1];
    logic [K_W-1:0]   k_pipe [0:BRAM_LATENCY-1];
    logic             valid_pipe [0:BRAM_LATENCY-1];
    logic             clear_pipe [0:BRAM_LATENCY-1];
    logic             cmp_valid_pipe [0:BRAM_LATENCY-1];
    logic             cmp_clear_pipe [0:BRAM_LATENCY-1];

    logic result_latched;

    assign o_s_ram_we   = s_we;
    assign o_s_ram_addr = s_addr;
    assign o_s_ram_data = s_data;
    assign scaled_store_data = 32'($signed(result_latch[store_j]) >>> SQRT_SHIFT);

    q_ram u_q_ram (
        .clka  (i_clock),
        .ena   (1'b1),
        .wea   (i_wea_q),
        .addra (i_addra_q),
        .dina  (i_dina_q),
        .douta (),

        .clkb  (i_clock),
        .enb   (1'b1),
        .web   (1'b0),
        .addrb (q_addrb),
        .dinb  (32'd0),
        .doutb (q_doutb)
    );

    k_ram u_k_ram (
        .clka  (i_clock),
        .ena   (1'b1),
        .wea   (i_wea_k),
        .addra (i_addra_k),
        .dina  (i_dina_k),
        .douta (),

        .clkb  (i_clock),
        .enb   (1'b1),
        .web   (1'b0),
        .addrb (k_addrb),
        .dinb  (32'd0),
        .doutb (k_doutb)
    );

    v_ram u_v_ram (
        .clka  (i_clock),
        .ena   (1'b1),
        .wea   (i_wea_v),
        .addra (i_addra_v),
        .dina  (i_dina_v),
        .douta ()
    );

    s_ram u_s_ram (
    .clka  (i_clock),
    .wea   (s_ram_wea),
    .addra (s_ram_addra),
    .dina  (s_ram_dina),
    .clkb  (i_clock),
    .addrb (i_sram_addrb),
    .doutb (o_sram_doutb)
    );

    matmul_ip #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_PE(N_PE),
        .D_MODEL(D_MODEL),
        .N_COLS(D_HEAD)
    ) u_matmul (
        .i_clk          (i_clock),
        .i_reset_n      (i_reset_n),

        .i_preload_en   (matmul_preload_en),
        .i_preload_j    (matmul_preload_j),
        .i_preload_k    (matmul_preload_k),
        .i_preload_data (matmul_preload_data),

        .i_data_valid   (matmul_data_valid),
        .i_acc_clear    (matmul_acc_clear),
        .i_k_index      (matmul_k_index),
        .i_a_data       (matmul_a_data),

        .o_result_valid (matmul_result_valid),
        .o_result       (matmul_result),

        .i_col_base      ('0),           // = 0 vì N_PE = N_COLS, không tiling
        .o_result_col_base()             // bỏ qua
    );

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_PRELOAD_K,
        ST_PRELOAD_DRAIN,
        ST_COMPUTE_Q,
        ST_WAIT_RESULT,
        ST_STORE_ROW,
        ST_DONE
    } state_t;

    state_t state;



    assign q_addrb = (state == ST_COMPUTE_Q)
        ? 32'(row_i) * 32'(D_MODEL) + 32'(col_k)
        : '0;

    assign k_addrb = (state == ST_PRELOAD_K)
        ? 32'(row_j) * 32'(D_MODEL) + 32'(col_k)
        : '0;

    always_ff @(posedge i_clock or negedge i_reset_n) begin
        if (!i_reset_n) begin
            for (int p = 0; p < BRAM_LATENCY; p++) begin
                j_pipe[p]     <= '0;
                k_pipe[p]     <= '0;
                valid_pipe[p] <= 1'b0;
                clear_pipe[p] <= 1'b0;
                cmp_valid_pipe[p] <= 1'b0;
                cmp_clear_pipe[p] <= 1'b0;
            end
        end else begin
            j_pipe[0]     <= row_j;
            k_pipe[0]     <= col_k;
            valid_pipe[0] <= (state == ST_PRELOAD_K) || (state == ST_PRELOAD_DRAIN && drain_cnt < BRAM_LATENCY);
            clear_pipe[0] <= 1'b0;                              // ← clear_pipe không còn dùng

            cmp_valid_pipe[0] <= (state == ST_COMPUTE_Q);
            cmp_clear_pipe[0] <= (state == ST_COMPUTE_Q) && (col_k == '0);

            for (int p = 1; p < BRAM_LATENCY; p++) begin
                j_pipe[p]          <= j_pipe[p-1];
                k_pipe[p]          <= k_pipe[p-1];
                valid_pipe[p]      <= valid_pipe[p-1];
                clear_pipe[p]      <= clear_pipe[p-1];
                cmp_valid_pipe[p]  <= cmp_valid_pipe[p-1];
                cmp_clear_pipe[p]  <= cmp_clear_pipe[p-1];
            end
        end
    end

    assign matmul_preload_en   = (state == ST_PRELOAD_K || state == ST_PRELOAD_DRAIN) && valid_pipe[BRAM_LATENCY-1];
    assign matmul_preload_j    = j_pipe[BRAM_LATENCY-1];
    assign matmul_preload_k    = k_pipe[BRAM_LATENCY-1];
    assign matmul_preload_data = k_doutb[DATA_WIDTH-1:0];

    assign matmul_data_valid = cmp_valid_pipe[BRAM_LATENCY-1];
    assign matmul_acc_clear  = cmp_clear_pipe[BRAM_LATENCY-1];
    assign matmul_k_index    = k_pipe[BRAM_LATENCY-1];
    assign matmul_a_data     = q_doutb[DATA_WIDTH-1:0];

    assign s_ram_wea   = s_we;
    assign s_ram_addra = s_addr;
    assign s_ram_dina  = s_data;

    always_ff @(posedge i_clock or negedge i_reset_n) begin
        if (!i_reset_n) begin
            state             <= ST_IDLE;
            row_i             <= '0;
            row_j             <= '0;
            store_j           <= '0;
            col_k             <= '0;
            drain_cnt         <= '0;
            result_latch      <= '0;
            result_latched    <= 1'b0;
            s_we              <= 1'b0;
            s_addr            <= '0;
            s_data            <= '0;
            o_attn_score_done <= 1'b0;


        end else begin
            s_we <= 1'b0;

            if (matmul_result_valid) begin
                for (int r = 0; r < SEQ_LEN; r++) begin
                    result_latch[r] <= matmul_result[r];
                end
                result_latched <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    o_attn_score_done <= 1'b0;
                    row_i          <= '0;
                    row_j          <= '0;
                    store_j        <= '0;
                    col_k          <= '0;
                    drain_cnt      <= '0;
                    result_latched <= 1'b0;
                    if (i_start_attn_score) begin
                        state <= ST_PRELOAD_K;
                    end
                end

                ST_PRELOAD_K: begin
                    if (col_k == K_W'(D_MODEL - 1)) begin
                        col_k <= '0;
                        if (row_j == ROW_W'(SEQ_LEN - 1)) begin
                            row_j     <= '0;
                            drain_cnt <= '0;
                            state     <= ST_PRELOAD_DRAIN;
                        end else begin
                            row_j <= row_j + 1'b1;
                        end
                    end else begin
                        col_k <= col_k + 1'b1;
                    end
                end

                ST_PRELOAD_DRAIN: begin
                    drain_cnt <= drain_cnt + 1'b1;
                    if (drain_cnt == 3'd3) begin
                        drain_cnt <= '0;
                        col_k     <= '0;
                        row_i     <= '0;
                        state     <= ST_COMPUTE_Q;
                    end
                end

                ST_COMPUTE_Q: begin
                    if (col_k == K_W'(D_MODEL - 1)) begin
                        col_k     <= '0;
                        drain_cnt <= '0;
                        state     <= ST_WAIT_RESULT;
                    end else begin
                        col_k <= col_k + 1'b1;
                    end
                end

                ST_WAIT_RESULT: begin
                    drain_cnt <= drain_cnt + 1'b1;
                    if (result_latched) begin
                        result_latched <= 1'b0;
                        drain_cnt      <= '0;
                        store_j        <= '0;
                        state          <= ST_STORE_ROW;
                    end
                end

                ST_STORE_ROW: begin
                    s_we   <= 1'b1;
                    s_addr <= 32'(row_i) * 32'(SEQ_LEN) + 32'(store_j);
                    s_data <= scaled_store_data;

                    if (store_j == ROW_W'(SEQ_LEN - 1)) begin
                        if (row_i == ROW_W'(SEQ_LEN - 1)) begin
                            state <= ST_DONE;
                        end else begin
                            row_i   <= row_i + 1'b1;
                            col_k   <= '0;
                            store_j <= '0;
                            state   <= ST_COMPUTE_Q;
                        end
                    end else begin
                        store_j <= store_j + 1'b1;
                    end
                end

                ST_DONE: begin
                    o_attn_score_done <= 1'b1;
                    if (!i_start_attn_score) begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
    assign o_busy = (state != ST_IDLE) && (state != ST_DONE);
endmodule
