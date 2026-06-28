`timescale 1ns / 1ps

import axi_vip_pkg::*;
import axi_vip_0_pkg::*;
import axi_vip_1_pkg::*;

module tb_ip_axi_linear;

// ── Parameters ────────────────────────────────────────────────
localparam int D_MODEL    = 64;
localparam int DATA_WIDTH = 16;
localparam int SEQ_LEN    = 16;
localparam int N_PE       = 16;
localparam int D_HEAD     = 16;
localparam int QKV_DEPTH  = SEQ_LEN * D_MODEL;
localparam int S_DEPTH    = SEQ_LEN * SEQ_LEN;
localparam int S00_ADDR_W = 4;
localparam int S01_ADDR_W = 5;

// ── S00 register offsets ──────────────────────────────────────
localparam logic [31:0] S00_CTRL       = 32'h00;
localparam logic [31:0] S00_STATUS     = 32'h04;
localparam logic [31:0] S00_SCORE_ADDR = 32'h08;
localparam logic [31:0] S00_SCORE_DATA = 32'h0C;

// ── S01 register offsets ──────────────────────────────────────
localparam logic [31:0] S01_Q_ADDR  = 32'h00;
localparam logic [31:0] S01_Q_DATA  = 32'h04;
localparam logic [31:0] S01_K_ADDR  = 32'h08;
localparam logic [31:0] S01_K_DATA  = 32'h0C;
localparam logic [31:0] S01_V_ADDR  = 32'h10;
localparam logic [31:0] S01_V_DATA  = 32'h14;
localparam logic [31:0] S01_WE_CTRL = 32'h18;
localparam logic [31:0] S01_LOCK    = 32'h1C;

localparam int TIMEOUT_CYCLES = 200000;

localparam string MEM_Q      = "E:/DOWNLOAD/HCMUT/TTKS/src/mem files/golden model/q_ram.mem";
localparam string MEM_K      = "E:/DOWNLOAD/HCMUT/TTKS/src/mem files/golden model/k_ram.mem";
localparam string MEM_V      = "E:/DOWNLOAD/HCMUT/TTKS/src/mem files/golden model/v_ram.mem";
localparam string MEM_GOLDEN = "E:/DOWNLOAD/HCMUT/TTKS/src/mem files/golden model/golden_score.mem";

// ── Clock & Reset ──────────────────────────────────────────────
logic clk, resetn;
initial clk = 0;
always #5 clk = ~clk;

// ── AXI S00 signals ────────────────────────────────────────────
logic [S00_ADDR_W-1:0] s00_awaddr; logic [2:0] s00_awprot;
logic s00_awvalid, s00_awready;
logic [31:0] s00_wdata; logic [3:0] s00_wstrb;
logic s00_wvalid, s00_wready;
logic [1:0] s00_bresp; logic s00_bvalid, s00_bready;
logic [S00_ADDR_W-1:0] s00_araddr; logic [2:0] s00_arprot;
logic s00_arvalid, s00_arready;
logic [31:0] s00_rdata; logic [1:0] s00_rresp;
logic s00_rvalid, s00_rready;

// ── AXI S01 signals ────────────────────────────────────────────
logic [S01_ADDR_W-1:0] s01_awaddr; logic [2:0] s01_awprot;
logic s01_awvalid, s01_awready;
logic [31:0] s01_wdata; logic [3:0] s01_wstrb;
logic s01_wvalid, s01_wready;
logic [1:0] s01_bresp; logic s01_bvalid, s01_bready;
logic [S01_ADDR_W-1:0] s01_araddr; logic [2:0] s01_arprot;
logic s01_arvalid, s01_arready;
logic [31:0] s01_rdata; logic [1:0] s01_rresp;
logic s01_rvalid, s01_rready;

// ── VIP master 0 → S00_AXI ────────────────────────────────────
axi_vip_0 axi_vip_0_inst (
    .aclk    (clk),
    .aresetn (resetn),
    .m_axi_awaddr  (s00_awaddr),  .m_axi_awprot  (s00_awprot),
    .m_axi_awvalid (s00_awvalid), .m_axi_awready (s00_awready),
    .m_axi_wdata   (s00_wdata),   .m_axi_wstrb   (s00_wstrb),
    .m_axi_wvalid  (s00_wvalid),  .m_axi_wready  (s00_wready),
    .m_axi_bresp   (s00_bresp),   .m_axi_bvalid  (s00_bvalid),
    .m_axi_bready  (s00_bready),
    .m_axi_araddr  (s00_araddr),  .m_axi_arprot  (s00_arprot),
    .m_axi_arvalid (s00_arvalid), .m_axi_arready (s00_arready),
    .m_axi_rdata   (s00_rdata),   .m_axi_rresp   (s00_rresp),
    .m_axi_rvalid  (s00_rvalid),  .m_axi_rready  (s00_rready)
);

// ── VIP master 1 → S01_AXI ────────────────────────────────────
axi_vip_1 axi_vip_1_inst (
    .aclk    (clk),
    .aresetn (resetn),
    .m_axi_awaddr  (s01_awaddr),  .m_axi_awprot  (s01_awprot),
    .m_axi_awvalid (s01_awvalid), .m_axi_awready (s01_awready),
    .m_axi_wdata   (s01_wdata),   .m_axi_wstrb   (s01_wstrb),
    .m_axi_wvalid  (s01_wvalid),  .m_axi_wready  (s01_wready),
    .m_axi_bresp   (s01_bresp),   .m_axi_bvalid  (s01_bvalid),
    .m_axi_bready  (s01_bready),
    .m_axi_araddr  (s01_araddr),  .m_axi_arprot  (s01_arprot),
    .m_axi_arvalid (s01_arvalid), .m_axi_arready (s01_arready),
    .m_axi_rdata   (s01_rdata),   .m_axi_rresp   (s01_rresp),
    .m_axi_rvalid  (s01_rvalid),  .m_axi_rready  (s01_rready)
);

// ── DUT ───────────────────────────────────────────────────────
ip_axi_linear_0 #(
    .D_MODEL   (D_MODEL),
    .SEQ_LEN   (SEQ_LEN),
    .DATA_WIDTH(DATA_WIDTH),
    .N_PE      (N_PE),
    .D_HEAD    (D_HEAD)
) u_dut (
    .s00_axi_aclk    (clk),        .s00_axi_aresetn (resetn),
    .s00_axi_awaddr  (s00_awaddr), .s00_axi_awprot  (s00_awprot),
    .s00_axi_awvalid (s00_awvalid),.s00_axi_awready (s00_awready),
    .s00_axi_wdata   (s00_wdata),  .s00_axi_wstrb   (s00_wstrb),
    .s00_axi_wvalid  (s00_wvalid), .s00_axi_wready  (s00_wready),
    .s00_axi_bresp   (s00_bresp),  .s00_axi_bvalid  (s00_bvalid),
    .s00_axi_bready  (s00_bready),
    .s00_axi_araddr  (s00_araddr), .s00_axi_arprot  (s00_arprot),
    .s00_axi_arvalid (s00_arvalid),.s00_axi_arready (s00_arready),
    .s00_axi_rdata   (s00_rdata),  .s00_axi_rresp   (s00_rresp),
    .s00_axi_rvalid  (s00_rvalid), .s00_axi_rready  (s00_rready),
    .s01_axi_aclk    (clk),        .s01_axi_aresetn (resetn),
    .s01_axi_awaddr  (s01_awaddr), .s01_axi_awprot  (s01_awprot),
    .s01_axi_awvalid (s01_awvalid),.s01_axi_awready (s01_awready),
    .s01_axi_wdata   (s01_wdata),  .s01_axi_wstrb   (s01_wstrb),
    .s01_axi_wvalid  (s01_wvalid), .s01_axi_wready  (s01_wready),
    .s01_axi_bresp   (s01_bresp),  .s01_axi_bvalid  (s01_bvalid),
    .s01_axi_bready  (s01_bready),
    .s01_axi_araddr  (s01_araddr), .s01_axi_arprot  (s01_arprot),
    .s01_axi_arvalid (s01_arvalid),.s01_axi_arready (s01_arready),
    .s01_axi_rdata   (s01_rdata),  .s01_axi_rresp   (s01_rresp),
    .s01_axi_rvalid  (s01_rvalid), .s01_axi_rready  (s01_rready)
);

// ── VIP agent handles ─────────────────────────────────────────
axi_vip_0_mst_t mst0;
axi_vip_1_mst_t mst1;

// ── Memory arrays ─────────────────────────────────────────────
logic [31:0]        mem_q[0:QKV_DEPTH-1];
logic [31:0]        mem_k[0:QKV_DEPTH-1];
logic [31:0]        mem_v[0:QKV_DEPTH-1];
logic signed [31:0] golden_score[0:S_DEPTH-1];
logic signed [31:0] captured_score[0:S_DEPTH-1];

// ── Timing variables ──────────────────────────────────────────
real t_total_start, t_total_end;
real t_loadQ_start, t_loadQ_end;
real t_loadK_start, t_loadK_end;
real t_loadV_start, t_loadV_end;
real t_compute_start, t_compute_end;
real t_read_start, t_read_end;

// =============================================================
//  AXI helper tasks
// =============================================================
task automatic wr0(input logic [31:0] addr, input logic [31:0] data);
    xil_axi_resp_t resp;
    mst0.AXI4LITE_WRITE_BURST(addr, 3'b000, data, resp);
    if (resp !== XIL_AXI_RESP_OKAY)
        $display("[WARN][S00] Write 0x%0h resp=%0d", addr, resp);
endtask

task automatic rd0(input logic [31:0] addr, output logic [31:0] rdata);
    xil_axi_resp_t resp;
    mst0.AXI4LITE_READ_BURST(addr, 3'b000, rdata, resp);
    if (resp !== XIL_AXI_RESP_OKAY)
        $display("[WARN][S00] Read 0x%0h resp=%0d", addr, resp);
endtask

task automatic wr1(input logic [31:0] addr, input logic [31:0] data);
    xil_axi_resp_t resp;
    mst1.AXI4LITE_WRITE_BURST(addr, 3'b000, data, resp);
    if (resp !== XIL_AXI_RESP_OKAY)
        $display("[WARN][S01] Write 0x%0h resp=%0d", addr, resp);
endtask

task automatic rd1(input logic [31:0] addr, output logic [31:0] rdata);
    xil_axi_resp_t resp;
    mst1.AXI4LITE_READ_BURST(addr, 3'b000, rdata, resp);
    if (resp !== XIL_AXI_RESP_OKAY)
        $display("[WARN][S01] Read 0x%0h resp=%0d", addr, resp);
endtask

// =============================================================
//  Task: Nạp 1 RAM qua S01
// =============================================================
task automatic load_ram_s01(
    input logic [31:0] mem    [],
    input int          depth,
    input logic [31:0] addr_reg,
    input logic [31:0] data_reg,
    input logic [31:0] we_bit
);
    logic [31:0] lock_val;
    rd1(S01_LOCK, lock_val);
    if (lock_val[0]) begin
        $display("[ERROR] LOCK=1 — DUT busy, khong the nap RAM!");
        return;
    end
    for (int i = 0; i < depth; i++) begin
        wr1(addr_reg,    32'(i));
        wr1(data_reg,    mem[i]);
        wr1(S01_WE_CTRL, we_bit);
    end
    wr1(S01_WE_CTRL, 32'h0);
endtask

// =============================================================
//  Task: Poll STATUS đến khi done
// =============================================================
task automatic wait_done();
    logic [31:0] status;
    int cnt;
    cnt = 0;
    do begin
        rd0(S00_STATUS, status);
        cnt++;
        if (cnt >= TIMEOUT_CYCLES) begin
            $display("[ERROR] TIMEOUT — attn_score_done khong len!");
            $finish;
        end
    end while (status[0] == 1'b0);
endtask

// =============================================================
//  Task: Đọc toàn bộ score qua S00
// =============================================================
task automatic read_all_scores();
    logic [31:0] rdata;
    for (int k = 0; k < S_DEPTH; k++) begin
        wr0(S00_SCORE_ADDR, 32'(k));
        @(posedge clk);
        @(posedge clk);
        rd0(S00_SCORE_DATA, rdata);
        captured_score[k] = $signed(rdata);
    end
endtask

// =============================================================
//  Task: So sánh DUT vs golden
// =============================================================
task automatic compare_score();
    int fail;
    fail = 0;
    $display("\n===== SO SANH CUOI (DUT vs GOLDEN) =====");
    for (int k = 0; k < S_DEPTH; k++) begin
        if (captured_score[k] !== golden_score[k]) begin
            $display("  FAIL [%0d][%0d] DUT=%0d golden=%0d",
                     k/SEQ_LEN, k%SEQ_LEN,
                     $signed(captured_score[k]),
                     $signed(golden_score[k]));
            fail++;
        end
    end
    if (fail == 0) $display("  [PASS] All %0d correct.", S_DEPTH);
    else           $display("  [FAIL] %0d / %0d wrong.", fail, S_DEPTH);
endtask

// =============================================================
//  Task: Ghi output file
// =============================================================
task automatic write_sram_output();
    int fd;
    fd = $fopen("E:/DOWNLOAD/HCMUT/TTKS/src/mem files/rtl/sram_output.mem", "w");
    if (fd == 0) begin
        $display("[ERROR] Khong mo duoc file sram_output.mem!");
        return;
    end
    for (int k = 0; k < S_DEPTH; k++)
        $fwrite(fd, "%08h\n", captured_score[k]);
    $fclose(fd);
    $display("[TB] Da ghi sram_output.mem (%0d entries)", S_DEPTH);
endtask

// =============================================================
//  Main
// =============================================================
initial begin
    $readmemh(MEM_Q,      mem_q);
    $readmemh(MEM_K,      mem_k);
    $readmemh(MEM_V,      mem_v);
    $readmemh(MEM_GOLDEN, golden_score);

    mst0 = new("mst0", tb_ip_axi_linear.axi_vip_0_inst.inst.IF);
    mst1 = new("mst1", tb_ip_axi_linear.axi_vip_1_inst.inst.IF);
    mst0.start_master();
    mst1.start_master();

    resetn = 1'b0;
    repeat(10) @(posedge clk);
    resetn = 1'b1;
    repeat(5)  @(posedge clk);

    t_total_start = $realtime;

    // Nạp Q/K/V RAM
    t_loadQ_start = $realtime;
    load_ram_s01(mem_q, QKV_DEPTH, S01_Q_ADDR, S01_Q_DATA, 32'h1);
    t_loadQ_end = $realtime;

    t_loadK_start = $realtime;
    load_ram_s01(mem_k, QKV_DEPTH, S01_K_ADDR, S01_K_DATA, 32'h2);
    t_loadK_end = $realtime;

    t_loadV_start = $realtime;
    load_ram_s01(mem_v, QKV_DEPTH, S01_V_ADDR, S01_V_DATA, 32'h4);
    t_loadV_end = $realtime;

    // Start
    wr0(S00_CTRL, 32'h1);
    t_compute_start = $realtime;
    wait_done();
    t_compute_end = $realtime;

    repeat(5) @(posedge clk);
    wr0(S00_CTRL, 32'h0);
    repeat(3) @(posedge clk);

    // Đọc và so sánh
    t_read_start = $realtime;
    read_all_scores();
    t_read_end = $realtime;

    compare_score();
    write_sram_output();

    t_total_end = $realtime;

    $display("\n===== TIMING SUMMARY =====");
    $display("  Load Q   : %0.1f ns", t_loadQ_end   - t_loadQ_start);
    $display("  Load K   : %0.1f ns", t_loadK_end   - t_loadK_start);
    $display("  Load V   : %0.1f ns", t_loadV_end   - t_loadV_start);
    $display("  Compute  : %0.1f ns", t_compute_end - t_compute_start);
    $display("  Read     : %0.1f ns", t_read_end    - t_read_start);
    $display("  TOTAL    : %0.1f ns", t_total_end   - t_total_start);
    $display("==========================");
    $finish;
end

// ── Watchdog ──────────────────────────────────────────────────
initial begin
    #50_000_000;
    $display("[WATCHDOG] Forced finish sau 50ms.");
    $finish;
end

endmodule