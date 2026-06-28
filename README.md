# ip_axi_linear version 4.0 — Module Reference Tables
Thực hiện phép nhân matmul hai ma trận Q, K tính attention score được đóng gói thành ip với hai giao diện slave:
- Slave0 thực hiện control quá trình compute, interface AXI Lite.
- Slave1 thực hiện nạp data Q, K vào BRAM q_ram, k_ram, interface AXI Lite.

<table>
  <tr>
    <td align="center">
      <img width="500" src="https://github.com/user-attachments/assets/2ca808b1-cf00-4179-89d2-5f062b4ccd97"/>
      <br/>
      <em>Hình 1: Sơ đồ khối cấu trúc thực thi linear</em>
    </td>
    <td align="center">
      <img width="300" src="https://github.com/user-attachments/assets/80748973-c535-4d21-9e02-10392a6c06a0"/>
      <br/>
      <em>Hình 2: Kết quả đóng gói ip axi linear</em>
    </td>
  </tr>
</table>

## 1. Tổng quan số module & hierarchy

```
ip_axi_linear_0  (AXI Wrapper — Top)
├── ip_axi_linear_slave_lite_v4_0_S00_AXI_inst   (S00: CTRL / STATUS / SCORE)
├── ip_axi_linear_slave_lite_v4_0_S01_AXI_inst   (S01: nạp Q / K / V RAM)
└── u_linear  ─── linear  (RTL Core)
        ├── u_q_ram   ─── q_ram   (blk_mem_gen, True Dual-Port)
        ├── u_k_ram   ─── k_ram   (blk_mem_gen, True Dual-Port)
        ├── u_v_ram   ─── v_ram   (blk_mem_gen, Simple Dual-Port)
        ├── u_s_ram   ─── s_ram   (blk_mem_gen, Simple Dual-Port)
        └── u_matmul  ─── matmul_ip_0  (Packaged IP — Systolic Array)
                └── pe_unit × N_PE   (Processing Element, generated)
```

| Cấp | Module | Instance name | File | Ghi chú |
|-----|--------|--------------|------|---------|
| Top | `ip_axi_linear` | `ip_axi_linear_0` | `ip_axi_linear.v` | AXI4-Lite wrapper, Vivado packaged |
| L1 | `ip_axi_linear_slave_lite_v4_0_S00_AXI` | `S00_AXI_inst` | `..._S00_AXI.v` | Slave 0: CTRL/STATUS/SCORE |
| L1 | `ip_axi_linear_slave_lite_v4_0_S01_AXI` | `S01_AXI_inst` | `..._S01_AXI.v` | Slave 1: nạp Q/K/V RAM |
| L1 | `linear` | `u_linear` | `linear.sv` | RTL core tính Attention Score |
| L2 | `q_ram` (blk_mem_gen) | `u_q_ram` | IP catalog | True Dual-Port BRAM 4096×32 |
| L2 | `k_ram` (blk_mem_gen) | `u_k_ram` | IP catalog | True Dual-Port BRAM 4096×32 |
| L2 | `v_ram` (blk_mem_gen) | `u_v_ram` | IP catalog | Simple Dual-Port BRAM 4096×32 |
| L2 | `s_ram` (blk_mem_gen) | `u_s_ram` | IP catalog | Simple Dual-Port BRAM 4096×32 |
| L2 | `matmul_ip` | `u_matmul` (instance: `matmul_ip_0`) | `matmul_ip.sv` | Systolic array, Vivado packaged |
| L3 | `pe_unit` | generated × N_PE | trong `matmul_ip.sv` | Processing Element |

---

## 2. Parameters từng module

### 2.1 `linear` (RTL Core)

| Parameter | Default | Ý nghĩa |
|-----------|---------|---------|
| `D_MODEL` | `64` | Số chiều embedding |
| `SEQ_LEN` | `64` | Độ dài chuỗi |
| `DATA_WIDTH` | `16` | Bit width dữ liệu Q/K |
| `N_PE` | `64` | Số Processing Element song song |
| `D_HEAD` | `64` | Số cột của ma trận K (= SEQ_LEN cho Q·Kᵀ) |

**Localparams:**

| Localparam | Công thức | Giá trị (default) | Ý nghĩa |
|------------|-----------|-------------------|---------|
| `QK_DEPTH` | `SEQ_LEN × D_MODEL` | `4096` | Depth của Q/K/V BRAM |
| `S_DEPTH` | `SEQ_LEN × SEQ_LEN` | `4096` | Depth của Score BRAM |
| `QK_ADDR_W` | `clog2(QK_DEPTH)` | `12` | Address width Q/K BRAM |
| `S_ADDR_W` | `clog2(S_DEPTH)` | `12` | Address width Score BRAM |
| `K_W` | `clog2(D_MODEL)` | `6` | Index cột K |
| `ROW_W` | `clog2(SEQ_LEN)` | `6` | Index hàng |
| `SQRT_SHIFT` | `clog2(D_MODEL)/2` | `3` | Right-shift ≈ ÷√64 |
| `BRAM_LATENCY` | — | `2` | Latency BRAM registered output |

---

### 2.2 `matmul_ip` (Systolic Array)

| Parameter | Giá trị trong project | Ý nghĩa |
|-----------|----------------------|---------|
| `DATA_WIDTH` | `16` | Bit width input/output |
| `N_PE` | `64` | Số PE song song |
| `D_MODEL` | `64` | Chiều k (độ dài dot product) |
| `N_COLS` | `64` (ánh xạ từ `D_HEAD`) | Số cột của B = số cột kết quả C |

**Localparams:**

| Localparam | Công thức | Giá trị | Ý nghĩa |
|------------|-----------|---------|---------|
| `N_TILES` | `ceil(N_COLS / N_PE)` | `1` | Số tile (= 1 khi N_PE = N_COLS) |
| `J_W` | `clog2(N_PE)` | `6` | Bit width của `i_preload_j` |
| `C_W` | `clog2(N_COLS)` | `6` | Bit width của `i_col_base` |

---

### 2.3 `pe_unit` (Processing Element)

| Localparam | Công thức | Giá trị | Ý nghĩa |
|------------|-----------|---------|---------|
| `ACC_WIDTH` | `DATA_WIDTH×2 + clog2(D_MODEL)` | `38` | Bit width accumulator (tránh overflow) |
| `FRAC_BITS` | `DATA_WIDTH / 2` | `8` | Số bit fraction cho Round-to-Nearest-Even |

---

### 2.4 `ip_axi_linear` (AXI Wrapper — Top)

| Parameter | Default | Ý nghĩa |
|-----------|---------|---------|
| `D_MODEL` | `64` | Chiều embedding |
| `SEQ_LEN` | `64` | Độ dài chuỗi |
| `DATA_WIDTH` | `16` | Bit width dữ liệu |
| `N_PE` | `64` | Số PE trong matmul |
| `D_HEAD` | `64` | Số cột K |
| `C_S00_AXI_DATA_WIDTH` | `32` | AXI data width S00 |
| `C_S00_AXI_ADDR_WIDTH` | `4` | AXI addr width S00 |
| `C_S01_AXI_DATA_WIDTH` | `32` | AXI data width S01 |
| `C_S01_AXI_ADDR_WIDTH` | `5` | AXI addr width S01 |

---

## 3. IP RAM — Thông tin chi tiết (blk_mem_gen)

### 3.1 Tổng quan

| RAM | Instance | Loại | Depth × Width | Dùng để |
|-----|----------|------|--------------|---------|
| `q_ram` | `u_q_ram` | True Dual-Port | 4096 × 32 bit | Lưu ma trận Q |
| `k_ram` | `u_k_ram` | True Dual-Port | 4096 × 32 bit | Lưu ma trận K |
| `v_ram` | `u_v_ram` | Simple Dual-Port | 4096 × 32 bit | Lưu ma trận V (chưa dùng trong tính score) |
| `s_ram` | `u_s_ram` | Simple Dual-Port | 4096 × 32 bit | Lưu Attention Score kết quả |

### 3.2 Cấu hình Port

| RAM | Port A — vai trò | Port A — tín hiệu | Port B — vai trò | Port B — tín hiệu |
|-----|-----------------|-------------------|-----------------|-------------------|
| `q_ram` | Write từ AXI (S01) | `wea`, `addra`, `dina` | Read từ FSM | `addrb`, `doutb` |
| `k_ram` | Write từ AXI (S01) | `wea`, `addra`, `dina` | Read từ FSM | `addrb`, `doutb` |
| `v_ram` | Write từ AXI (S01) | `wea`, `addra`, `dina` | Không kết nối | — |
| `s_ram` | Write từ FSM (lưu score) | `wea`, `addra`, `dina` | Read từ AXI (S00) | `addrb`, `doutb` |

### 3.3 Latency

| RAM | Loại | Latency Port A | Latency Port B | Ghi chú |
|-----|------|:--------------:|:--------------:|---------|
| `q_ram` | True Dual-Port | 2 cycle | 2 cycle | FSM bù bằng pipeline 2 stage |
| `k_ram` | True Dual-Port | 2 cycle | 2 cycle | FSM bù bằng pipeline 2 stage |
| `v_ram` | Simple Dual-Port | 2 cycle | N/A | Port B không kết nối |
| `s_ram` | Simple Dual-Port | 2 cycle | 1 cycle | Port B latency thấp hơn cho AXI read |

### 3.4 Đặc điểm từng RAM

**q_ram & k_ram — True Dual-Port BRAM**
- Cả 2 port đều có thể đọc và ghi
- Port A: write-only từ AXI (`douta` không dùng)
- Port B: read-only từ FSM (`web=0`, `dinb=0`)
- Enable: `ena`, `enb` luôn active (always enabled)

**v_ram — Simple Dual-Port BRAM**
- Port A: write, Port B: read (cố định theo loại)
- Chỉ Port A được instantiate trong `linear.sv`; Port B không kết nối (V chưa tham gia tính Attention Score)

**s_ram — Simple Dual-Port BRAM**
- Port A: ghi bởi FSM state `ST_STORE_ROW` — lưu kết quả `result_latch[j] >>> SQRT_SHIFT`
- Port B: đọc bởi AXI S00 qua offset `SCORE_ADDR`/`SCORE_DATA`
- Port A & B: `ena`, `enb` luôn active (always enabled)
- Latency Port B = 1 cycle (thấp hơn Q/K RAM) → đọc score qua AXI với margin nhỏ hơn

---

## 4. AXI Register Map

### S00_AXI — CTRL / STATUS / SCORE (ADDR_WIDTH=4)

| Offset | Tên | R/W | Nội dung |
|--------|-----|:---:|---------|
| `0x00` | `CTRL` | W | `bit[0]` = `i_start_attn_score` — pulse để bắt đầu tính |
| `0x04` | `STATUS` | R | `{31'd0, i_attn_score_done}` — 1 khi hoàn thành |
| `0x08` | `SCORE_ADDR` | W | Index vào Score RAM (0..4095) |
| `0x0C` | `SCORE_DATA` | R | Data từ Score RAM port B |

> **Lưu ý:** Ghi `SCORE_ADDR` trước, sau đó mới đọc `SCORE_DATA` (latency 1 cycle port B).

### S01_AXI — Nạp Q/K/V RAM (ADDR_WIDTH=5)

| Offset | Tên | R/W | Nội dung |
|--------|-----|:---:|---------|
| `0x00` | `Q_ADDR` | W | Address ghi vào Q RAM |
| `0x04` | `Q_DATA` | W | Data ghi vào Q RAM |
| `0x08` | `K_ADDR` | W | Address ghi vào K RAM |
| `0x0C` | `K_DATA` | W | Data ghi vào K RAM |
| `0x10` | `V_ADDR` | W | Address ghi vào V RAM |
| `0x14` | `V_DATA` | W | Data ghi vào V RAM |
| `0x18` | `WE_CTRL` | W | `bit[0]`=wea_q, `bit[1]`=wea_k, `bit[2]`=wea_v |
| `0x1C` | `LOCK` | R | `{31'd0, i_busy}` — 1 khi DUT đang tính (bảo vệ ghi RAM) |

> **Cơ chế bảo vệ:** `wea_x = WE_CTRL[x] & (~i_busy)` — không ghi RAM khi đang tính.

---

## 5. FSM `linear` — 7 states

| State | Điều kiện vào | Hoạt động | Điều kiện ra |
|-------|--------------|-----------|-------------|
| `ST_IDLE` | Reset / done deassert | Chờ | `i_start_attn_score` → `ST_PRELOAD_K` |
| `ST_PRELOAD_K` | Từ IDLE | Đọc toàn bộ K BRAM (SEQ_LEN × D_MODEL entries) qua port B, feed vào matmul preload; dùng pipeline 2 stage bù BRAM latency | Xong → `ST_PRELOAD_DRAIN` |
| `ST_PRELOAD_DRAIN` | Từ PRELOAD_K | Chờ drain 4 cycle để flush pipeline | → `ST_COMPUTE_Q` |
| `ST_COMPUTE_Q` | Từ PRELOAD_DRAIN hoặc STORE_ROW | Đọc 1 hàng Q[row_i] (D_MODEL entries), feed vào matmul compute | `col_k == D_MODEL-1` → `ST_WAIT_RESULT` |
| `ST_WAIT_RESULT` | Từ COMPUTE_Q | Chờ `matmul_result_valid`; latch kết quả vào `result_latch[0..63]` | `result_latched` → `ST_STORE_ROW` |
| `ST_STORE_ROW` | Từ WAIT_RESULT | Ghi từng phần tử `result_latch[j] >>> SQRT_SHIFT` vào s_ram; addr = `row_i × SEQ_LEN + j` | Còn hàng: row_i++ → `ST_COMPUTE_Q`; hết hàng → `ST_DONE` |
| `ST_DONE` | Từ STORE_ROW | `o_attn_score_done = 1` | `i_start_attn_score` deassert → `ST_IDLE` |
