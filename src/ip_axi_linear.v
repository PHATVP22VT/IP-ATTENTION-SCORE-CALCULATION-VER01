`timescale 1 ns / 1 ps

	module ip_axi_linear #
	(
		// Users to add parameters here
		parameter integer D_MODEL    = 64,
		parameter integer SEQ_LEN    = 64,
		parameter integer DATA_WIDTH = 16,
		parameter int N_PE = 64,
		parameter int D_HEAD = 64,
		
		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 4,

		// Parameters of Axi Slave Bus Interface S01_AXI
		parameter integer C_S01_AXI_DATA_WIDTH	= 32,
		parameter integer C_S01_AXI_ADDR_WIDTH	= 5
	)
	(
		// Users to add ports here
        output logic [31:0] o_s_ram_data,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready,

		// Ports of Axi Slave Bus Interface S01_AXI
		input wire  s01_axi_aclk,
		input wire  s01_axi_aresetn,
		input wire [C_S01_AXI_ADDR_WIDTH-1 : 0] s01_axi_awaddr,
		input wire [2 : 0] s01_axi_awprot,
		input wire  s01_axi_awvalid,
		output wire  s01_axi_awready,
		input wire [C_S01_AXI_DATA_WIDTH-1 : 0] s01_axi_wdata,
		input wire [(C_S01_AXI_DATA_WIDTH/8)-1 : 0] s01_axi_wstrb,
		input wire  s01_axi_wvalid,
		output wire  s01_axi_wready,
		output wire [1 : 0] s01_axi_bresp,
		output wire  s01_axi_bvalid,
		input wire  s01_axi_bready,
		input wire [C_S01_AXI_ADDR_WIDTH-1 : 0] s01_axi_araddr,
		input wire [2 : 0] s01_axi_arprot,
		input wire  s01_axi_arvalid,
		output wire  s01_axi_arready,
		output wire [C_S01_AXI_DATA_WIDTH-1 : 0] s01_axi_rdata,
		output wire [1 : 0] s01_axi_rresp,
		output wire  s01_axi_rvalid,
		input wire  s01_axi_rready
	);

	//Add user local parameter here

	//Add user wire internal logic
	wire                   start_attn_score;
	wire                   attn_score_done;
	wire [31:0]   sram_addrb;
	wire [31:0]            sram_doutb;
	wire 					busy;

	wire [31:0] addra_q; wire [31:0] dina_q; wire wea_q;
	wire [31:0] addra_k; wire [31:0] dina_k; wire wea_k;
	wire [31:0] addra_v; wire [31:0] dina_v; wire wea_v;
// Instantiation of Axi Bus Interface S00_AXI
	ip_axi_linear_slave_lite_v4_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH (C_S00_AXI_ADDR_WIDTH),
		.D_MODEL            (D_MODEL),              // ← thêm
		.SEQ_LEN            (SEQ_LEN),              // ← thêm
		.DATA_WIDTH         (DATA_WIDTH)            // ← thêm
	) ip_axi_linear_slave_lite_v4_0_S00_AXI_inst (
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready),

		.o_start_attn_score (start_attn_score),     // ← thêm
		.i_attn_score_done  (attn_score_done),      // ← thêm
		.o_sram_addrb       (sram_addrb),           // ← thêm
		.i_sram_doutb       (sram_doutb)            // ← thêm
	);

// Instantiation of Axi Bus Interface S01_AXI
	ip_axi_linear_slave_lite_v4_0_S01_AXI # ( 
		.C_S_AXI_DATA_WIDTH (C_S01_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH (C_S01_AXI_ADDR_WIDTH),
		.D_MODEL            (D_MODEL),              // ← thêm
		.SEQ_LEN            (SEQ_LEN),              // ← thêm
		.DATA_WIDTH         (DATA_WIDTH)            // ← thêm
	) ip_axi_linear_slave_lite_v4_0_S01_AXI_inst (
		.S_AXI_ACLK(s01_axi_aclk),
		.S_AXI_ARESETN(s01_axi_aresetn),
		.S_AXI_AWADDR(s01_axi_awaddr),
		.S_AXI_AWPROT(s01_axi_awprot),
		.S_AXI_AWVALID(s01_axi_awvalid),
		.S_AXI_AWREADY(s01_axi_awready),
		.S_AXI_WDATA(s01_axi_wdata),
		.S_AXI_WSTRB(s01_axi_wstrb),
		.S_AXI_WVALID(s01_axi_wvalid),
		.S_AXI_WREADY(s01_axi_wready),
		.S_AXI_BRESP(s01_axi_bresp),
		.S_AXI_BVALID(s01_axi_bvalid),
		.S_AXI_BREADY(s01_axi_bready),
		.S_AXI_ARADDR(s01_axi_araddr),
		.S_AXI_ARPROT(s01_axi_arprot),
		.S_AXI_ARVALID(s01_axi_arvalid),
		.S_AXI_ARREADY(s01_axi_arready),
		.S_AXI_RDATA(s01_axi_rdata),
		.S_AXI_RRESP(s01_axi_rresp),
		.S_AXI_RVALID(s01_axi_rvalid),
		.S_AXI_RREADY(s01_axi_rready),

		.i_busy    (busy),               // ← thêm
		.o_addra_q (addra_q), .o_dina_q (dina_q), .o_wea_q (wea_q),// ← thêm
		.o_addra_k (addra_k), .o_dina_k (dina_k), .o_wea_k (wea_k),// ← thêm
		.o_addra_v (addra_v), .o_dina_v (dina_v), .o_wea_v (wea_v)// ← thêm
	);

	// Add user logic here
	linear #(
		.D_MODEL   (D_MODEL),
		.SEQ_LEN   (SEQ_LEN),
		.DATA_WIDTH(DATA_WIDTH),
		.N_PE(N_PE),
		.D_HEAD(D_HEAD)
	) u_linear (
		.i_clock            (s00_axi_aclk),
		.i_reset_n          (s00_axi_aresetn),
		.i_start_attn_score (start_attn_score),
		.o_attn_score_done  (attn_score_done),
		.i_dina_q           (dina_q),  .i_addra_q (addra_q), .i_wea_q (wea_q),
		.i_dina_k           (dina_k),  .i_addra_k (addra_k), .i_wea_k (wea_k),
		.i_dina_v           (dina_v),  .i_addra_v (addra_v), .i_wea_v (wea_v),
		.i_sram_addrb       (sram_addrb),
		.o_sram_doutb       (sram_doutb),
		.o_s_ram_we         (),        // không cần kéo ra ngoài IP
		.o_s_ram_addr       (),
		.o_s_ram_data       (o_s_ram_data),
		.o_busy(busy)
	);
	// User logic ends

	endmodule