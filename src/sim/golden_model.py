import numpy as np
import os
import math

# ==============================================================================
# golden_model.py — Bit-true reference model for ip_axi_linear
#
# Parameter mapping (must match ip_axi_linear / linear.sv):
#   D_MODEL    : inner dimension of Q×Kᵀ dot product  → linear.sv D_MODEL
#   SEQ_LEN    : number of Q rows (output rows of S)  → linear.sv SEQ_LEN
#   D_HEAD     : number of K rows (output cols of S)  → linear.sv D_HEAD
#   N_PE       : number of parallel PEs               → linear.sv N_PE (= D_HEAD, 1-tile)
#   DATA_WIDTH : element bit width, signed fixed-point → linear.sv DATA_WIDTH
#   FRAC_BITS  : fractional bits in Q<INT>.<FRAC> rep  → pe_unit FRAC_BITS = DATA_WIDTH/2
#   SQRT_SHIFT : output scaling right-shift            → linear.sv $clog2(D_MODEL)/2
#
# Scaling pipeline (bit-true to RTL):
#   mac_sum  = Σ Q_int[i][k] * K_int[j][k]           (38-bit accumulator, pe_unit)
#   pe_out   = round_half_to_even(mac_sum / 2^FRAC_BITS)  → DATA_WIDTH bits
#   score    = arithmetic_right_shift(pe_out, SQRT_SHIFT)  → DATA_WIDTH bits (linear.sv)
# ==============================================================================

# ==============================================================================
# DEFAULT PARAMETERS — match ip_axi_linear defaults
# ==============================================================================
DEFAULT_D_MODEL    = 64
DEFAULT_SEQ_LEN    = 64
DEFAULT_D_HEAD     = 64
DEFAULT_N_PE       = 64     # informational only; must equal D_HEAD for 1-tile mode
DEFAULT_DATA_WIDTH = 16
DEFAULT_RUN_MODE   = 2
DEFAULT_UNIFORM    = 50

ROM_DEPTH = 2048            # exp LUT depth (fixed)

# ==============================================================================
# OUTPUT PATHS
# ==============================================================================
COE_OUT_PATH = r"E:\DOWNLOAD\HCMUT\TTKS\src\coe files\golden model"
MEM_OUT_PATH = r"E:\DOWNLOAD\HCMUT\TTKS\src\mem files\golden model"

# ==============================================================================
# INPUT UTILITIES
# ==============================================================================
def get_int_input(prompt, default, min_val=None, max_val=None):
    while True:
        raw = input(f"{prompt} [default={default}]: ").strip()
        if raw == "":
            return default
        try:
            val = int(raw)
        except ValueError:
            print("  -> Invalid integer.")
            continue
        if min_val is not None and val < min_val:
            print(f"  -> Must be >= {min_val}.")
            continue
        if max_val is not None and val > max_val:
            print(f"  -> Must be <= {max_val}.")
            continue
        return val


def get_mode_input(default):
    while True:
        raw = input(f"RUN_MODE (1=Uniform, 2=Random) [default={default}]: ").strip()
        if raw == "":
            return default
        if raw in ("1", "2"):
            return int(raw)
        print("  -> Enter 1 or 2.")


# ==============================================================================
# DERIVED PARAMETERS (bit-true to RTL)
# ==============================================================================
def derive_params(D_MODEL, DATA_WIDTH):
    """
    Compute derived constants exactly as RTL does.
    pe_unit   : FRAC_BITS  = DATA_WIDTH / 2          (integer division)
    linear.sv : SQRT_SHIFT = $clog2(D_MODEL) / 2     (integer division)
    """
    frac_bits  = DATA_WIDTH // 2
    clog2_dm   = int(math.ceil(math.log2(D_MODEL))) if D_MODEL > 1 else 1
    sqrt_shift = clog2_dm // 2
    return frac_bits, sqrt_shift


# ==============================================================================
# FIXED-POINT CONVERSION
# ==============================================================================
def float_to_fixed(val_array, frac_bits):
    """Convert float array to signed fixed-point integer (DATA_WIDTH bits)."""
    scaled = np.round(val_array * float(1 << frac_bits))
    return np.clip(scaled, -32768, 32767).astype(np.int64)


# ==============================================================================
# ROUNDING — bit-true to pe_unit round-to-nearest-even
#
# pe_unit RTL:
#   round_up = acc[FRAC_BITS-1] & (|acc[FRAC_BITS-2:0] | acc[FRAC_BITS])
#   o_result = acc[FRAC_BITS+DATA_WIDTH-1 : FRAC_BITS] + round_up
#
# This is round-half-to-even (banker's rounding) on the integer accumulator,
# truncating FRAC_BITS LSBs.
# ==============================================================================
def round_half_to_even_shift(acc_array, shift):
    """
    Arithmetic right-shift by `shift` bits with round-half-to-even,
    applied element-wise on a numpy int64 array.
    Matches pe_unit RTL accumulator truncation exactly.
    """
    half      = np.int64(1) << np.int64(shift - 1)   # 2^(shift-1)
    low_mask  = (np.int64(1) << np.int64(shift)) - np.int64(1)  # mask for shift LSBs
    remainder = acc_array & low_mask                  # bits being dropped
    quotient  = acc_array >> np.int64(shift)          # truncated result (arithmetic)

    # Half-boundary: remainder == half (exact 0.5)
    at_half   = (remainder == half)
    above_half = (remainder > half)

    # LSB of quotient (for even check)
    lsb       = quotient & np.int64(1)

    # Round up when: above half, OR at exactly half AND result is odd (round-to-even)
    round_up  = above_half | (at_half & (lsb != 0))

    return quotient + round_up.astype(np.int64)


# ==============================================================================
# ARITHMETIC RIGHT SHIFT (linear.sv SQRT_SHIFT stage)
# Truncation only — matches Verilog >>> on signed.
# ==============================================================================
def arith_right_shift(arr, shift):
    """Arithmetic right shift with truncation (no rounding). Matches >>> in Verilog."""
    return arr >> np.int64(shift)


# ==============================================================================
# EXP LUT
# ==============================================================================
def generate_exp_lut(frac_bits):
    lut = []
    for i in range(ROM_DEPTH):
        x     = -i / float(1 << frac_bits)
        val   = np.exp(x)
        q_val = int(np.round(val * float(1 << frac_bits)))
        if q_val == 0 and val > 0:
            q_val = 1
        lut.append(q_val)
    return lut


# ==============================================================================
# FILE OUTPUT HELPERS
# ==============================================================================
def _ensure(path):
    os.makedirs(path, exist_ok=True)

def write_coe_16(filename, data):
    try:
        _ensure(COE_OUT_PATH)
        fp = os.path.join(COE_OUT_PATH, filename)
        with open(fp, 'w') as f:
            f.write("memory_initialization_radix=16;\n")
            f.write("memory_initialization_vector=\n")
            for i, v in enumerate(data):
                sep = ";" if i == len(data) - 1 else ","
                f.write(f"{int(v) & 0xFFFF:04X}{sep}\n")
        print(f"[OK] COE 16-bit : {fp}")
    except Exception as e:
        print(f"[ERR] {filename}: {e}")

def write_coe_32(filename, data):
    try:
        _ensure(COE_OUT_PATH)
        fp = os.path.join(COE_OUT_PATH, filename)
        with open(fp, 'w') as f:
            f.write("memory_initialization_radix=16;\n")
            f.write("memory_initialization_vector=\n")
            for i, v in enumerate(data):
                sep = ";" if i == len(data) - 1 else ","
                f.write(f"{int(v) & 0xFFFFFFFF:08X}{sep}\n")
        print(f"[OK] COE 32-bit : {fp}")
    except Exception as e:
        print(f"[ERR] {filename}: {e}")

def write_mem_16(filename, data):
    try:
        _ensure(MEM_OUT_PATH)
        fp = os.path.join(MEM_OUT_PATH, filename)
        with open(fp, 'w') as f:
            for v in data:
                f.write(f"{int(v) & 0xFFFF:04X}\n")
        print(f"[OK] MEM 16-bit : {fp}")
    except Exception as e:
        print(f"[ERR] {filename}: {e}")

def write_mem_32(filename, data):
    try:
        _ensure(MEM_OUT_PATH)
        fp = os.path.join(MEM_OUT_PATH, filename)
        with open(fp, 'w') as f:
            for v in data:
                f.write(f"{int(v) & 0xFFFFFFFF:08X}\n")
        print(f"[OK] MEM 32-bit : {fp}")
    except Exception as e:
        print(f"[ERR] {filename}: {e}")

def write_golden_score(score_int):
    try:
        _ensure(MEM_OUT_PATH)
        fp = os.path.join(MEM_OUT_PATH, "golden_score.mem")
        with open(fp, 'w') as f:
            for v in score_int.flatten():
                f.write(f"{int(v) & 0xFFFFFFFF:08X}\n")
        print(f"[OK] golden_score.mem : {fp}")
    except Exception as e:
        print(f"[ERR] golden_score.mem: {e}")


# ==============================================================================
# GOLDEN COMPUTE — Phase 1: Q × Kᵀ scaled dot-product
#
# Matches RTL pipeline exactly:
#   1. pe_unit MAC: acc = Σ Q_int[i][k] * K_int[j][k]   (int64, no overflow for DATA_WIDTH=16)
#   2. pe_unit out: round_half_to_even(acc, FRAC_BITS)   → DATA_WIDTH bits
#   3. linear.sv  : arith_right_shift(pe_out, SQRT_SHIFT) → DATA_WIDTH bits (output reg)
#   4. linear.sv  : zero-extend to 32 bits for M_AXIS TDATA
# ==============================================================================
def compute_attention_score(Q_int, K_int, frac_bits, sqrt_shift, data_width):
    """
    Q_int : [SEQ_LEN × D_MODEL]  int64
    K_int : [D_HEAD  × D_MODEL]  int64
    returns Score_int : [SEQ_LEN × D_HEAD]  int64
    """
    # Step 1: accumulate (exact integer, no overflow for 16-bit inputs × 64 elements)
    mac_sum = np.dot(Q_int, K_int.T)                          # [SEQ_LEN × D_HEAD], int64

    # Step 2: pe_unit truncation with round-half-to-even at FRAC_BITS
    pe_out = round_half_to_even_shift(mac_sum, frac_bits)     # [SEQ_LEN × D_HEAD], int64

    # Clip to DATA_WIDTH signed range (pe_unit output register)
    max_val = (1 << (data_width - 1)) - 1
    min_val = -(1 << (data_width - 1))
    pe_out  = np.clip(pe_out, min_val, max_val)

    # Step 3: SQRT_SHIFT in linear.sv (arithmetic right shift, truncation)
    score = arith_right_shift(pe_out, sqrt_shift)             # [SEQ_LEN × D_HEAD], int64

    # Clip to DATA_WIDTH signed range (result_buffer register)
    score = np.clip(score, min_val, max_val)

    return score


# ==============================================================================
# GOLDEN COMPUTE — Phase 2: Softmax (row-wise)
# ==============================================================================
def compute_softmax(score_int, exp_lut, frac_bits):
    """
    score_int  : [SEQ_LEN × D_HEAD]  int64
    exp_lut    : list of int (ROM_DEPTH entries)
    returns weights_int : [SEQ_LEN × D_HEAD]  int64
    """
    exp_lut_arr = np.array(exp_lut, dtype=np.int64)
    max_score   = np.max(score_int, axis=1, keepdims=True)
    Z_int       = score_int - max_score

    exp_Z = np.zeros_like(Z_int)
    for i in range(Z_int.shape[0]):
        for j in range(Z_int.shape[1]):
            val = int(Z_int[i, j])
            if val <= 0:
                addr = (-val) & 0x7FF
                exp_Z[i, j] = exp_lut_arr[addr] if addr < ROM_DEPTH else 0

    sum_exp      = np.sum(exp_Z, axis=1, keepdims=True)
    weights_int  = (exp_Z * (1 << frac_bits)) // sum_exp
    return exp_Z, sum_exp, weights_int


# ==============================================================================
# PRINT / REPORT
# ==============================================================================
def print_report(Q_int, K_int, score_int, exp_Z, sum_exp, weights_int,
                 frac_bits, sqrt_shift, label=""):
    tag = f"[{label}] " if label else ""
    N_PRINT = 4   # elements to preview per row

    print("\n" + "=" * 70)
    print(f"  {tag}GOLDEN MODEL REPORT")
    print("=" * 70)

    print(f"\n[PARAMS] FRAC_BITS={frac_bits}  SQRT_SHIFT={sqrt_shift}"
          f"  divisor={1 << frac_bits} × {1 << sqrt_shift}"
          f" = {(1 << frac_bits) * (1 << sqrt_shift)}")

    SEQ_LEN, D_MODEL = Q_int.shape
    D_HEAD = K_int.shape[0]

    print(f"\n--- INPUT Q [{SEQ_LEN}×{D_MODEL}] and K [{D_HEAD}×{D_MODEL}]"
          f" (first {N_PRINT} cols) ---")
    for t in range(SEQ_LEN):
        q_str = " ".join(f"{int(Q_int[t,i]) & 0xFFFF:04x}({int(Q_int[t,i]):6})"
                         for i in range(min(N_PRINT, D_MODEL)))
        print(f"  Q[{t:2}]: {q_str}")
    for t in range(D_HEAD):
        k_str = " ".join(f"{int(K_int[t,i]) & 0xFFFF:04x}({int(K_int[t,i]):6})"
                         for i in range(min(N_PRINT, D_MODEL)))
        print(f"  K[{t:2}]: {k_str}")

    print(f"\n--- PHASE 1: ATTENTION SCORE [{SEQ_LEN}×{D_HEAD}] ---")
    flat = score_int.flatten()
    for i, v in enumerate(flat):
        vi = int(v)
        print(f"  [{i:3}]  {vi & 0xFFFFFFFF:08x}  ({vi:8})  {vi / float(1 << frac_bits):.4f}")

    print(f"\n--- PHASE 2: EXP VALUES [{SEQ_LEN}×{D_HEAD}] ---")
    flat_exp = exp_Z.flatten()
    for i, v in enumerate(flat_exp):
        vi = int(v)
        print(f"  [{i:3}]  {vi & 0xFFFF:04x}  ({vi:5})  {vi / float(1 << frac_bits):.4f}")
    for t in range(SEQ_LEN):
        sv = int(sum_exp[t, 0])
        print(f"  SUM_EXP row {t:2}: {sv}  ({sv / float(1 << frac_bits):.4f})")

    print(f"\n--- PHASE 3: SOFTMAX WEIGHTS [{SEQ_LEN}×{D_HEAD}] ---")
    flat_w = weights_int.flatten()
    for i, v in enumerate(flat_w):
        vi = int(v)
        print(f"  [{i:3}]  {vi & 0xFFFF:04x}  ({vi:5})  {vi / float(1 << frac_bits):.4f}")


# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":

    print("=" * 70)
    print("  ip_axi_linear GOLDEN MODEL")
    print("  Parameters must match ip_axi_linear / linear.sv exactly.")
    print("=" * 70)

    # ── 1. PARAMETERS (match ip_axi_linear port parameters) ─────────────────
    print("\n[STEP 1] RTL Parameters")
    D_MODEL    = get_int_input("  D_MODEL    (inner dot-product dim, RTL param D_MODEL)",
                               DEFAULT_D_MODEL, min_val=2)
    SEQ_LEN    = get_int_input("  SEQ_LEN    (Q rows = S rows,        RTL param SEQ_LEN)",
                               DEFAULT_SEQ_LEN, min_val=1)
    D_HEAD     = get_int_input("  D_HEAD     (K rows = S cols,         RTL param D_HEAD)",
                               DEFAULT_D_HEAD, min_val=1)
    N_PE       = get_int_input("  N_PE       (parallel PEs, must = D_HEAD for 1-tile)",
                               DEFAULT_N_PE, min_val=1)
    DATA_WIDTH = get_int_input("  DATA_WIDTH (element bit width, signed fixed-point)",
                               DEFAULT_DATA_WIDTH, min_val=2, max_val=32)

    # Validate N_PE
    if N_PE != D_HEAD:
        print(f"  [WARN] N_PE={N_PE} != D_HEAD={D_HEAD}. "
              f"Tiling mode: golden outputs N_PE cols per tile. "
              f"Script will compute full D_HEAD output (no tiling loop here).")

    # Validate D_MODEL is power-of-2 (SQRT_SHIFT is exact only for pow2)
    if (D_MODEL & (D_MODEL - 1)) != 0:
        print(f"  [WARN] D_MODEL={D_MODEL} is not power-of-2. "
              f"$clog2(D_MODEL)/2 in RTL may not equal log2(D_MODEL)/2. "
              f"Verify SQRT_SHIFT matches RTL manually.")

    # Derived — exactly as RTL
    FRAC_BITS, SQRT_SHIFT = derive_params(D_MODEL, DATA_WIDTH)
    print(f"\n  [DERIVED] FRAC_BITS={FRAC_BITS}  (pe_unit: DATA_WIDTH/2)")
    print(f"  [DERIVED] SQRT_SHIFT={SQRT_SHIFT} (linear.sv: $clog2({D_MODEL})/{2} = "
          f"{int(math.ceil(math.log2(D_MODEL))) if D_MODEL > 1 else 1}/{2})")
    print(f"  [DERIVED] Total scaling divisor = {1 << (FRAC_BITS + SQRT_SHIFT)}")

    # ── 2. RUN MODE ──────────────────────────────────────────────────────────
    print("\n[STEP 2] Data Generation Mode")
    RUN_MODE = get_mode_input(DEFAULT_RUN_MODE)

    UNIFORM_VAL = DEFAULT_UNIFORM
    if RUN_MODE == 1:
        UNIFORM_VAL = get_int_input(
            "  UNIFORM_VAL (integer fixed-point value, e.g. 50 = 50 LSB)",
            DEFAULT_UNIFORM)

    # ── 3. GENERATE Q, K, V ─────────────────────────────────────────────────
    print("\n[STEP 3] Generating Q, K, V")

    if RUN_MODE == 1:
        print(f"  Mode 1: Uniform, all elements = {UNIFORM_VAL}")
        Q_int = np.full((SEQ_LEN, D_MODEL), UNIFORM_VAL, dtype=np.int64)
        K_int = np.full((D_HEAD,  D_MODEL), UNIFORM_VAL, dtype=np.int64)
        V_int = np.full((SEQ_LEN, D_MODEL), UNIFORM_VAL, dtype=np.int64)

    else:  # RUN_MODE == 2
        print("  Mode 2: Random, seed=42, float range [-0.3, 0.3], Q<INT>.<FRAC> encoding")
        np.random.seed(42)
        Q_f   = np.random.uniform(-0.3, 0.3, (SEQ_LEN, D_MODEL)).astype(np.float32)
        K_f   = np.random.uniform(-0.3, 0.3, (D_HEAD,  D_MODEL)).astype(np.float32)
        V_f   = np.random.uniform(-0.3, 0.3, (SEQ_LEN, D_MODEL)).astype(np.float32)
        Q_int = float_to_fixed(Q_f, FRAC_BITS)
        K_int = float_to_fixed(K_f, FRAC_BITS)
        V_int = float_to_fixed(V_f, FRAC_BITS)

    print(f"  Q shape: {Q_int.shape}  K shape: {K_int.shape}  V shape: {V_int.shape}")
    print(f"  Q range: [{Q_int.min()}, {Q_int.max()}]")
    print(f"  K range: [{K_int.min()}, {K_int.max()}]")

    # ── 4. EXP LUT ───────────────────────────────────────────────────────────
    print("\n[STEP 4] Generating exp LUT")
    exp_lut = generate_exp_lut(FRAC_BITS)
    write_coe_16("exp_rom.coe", exp_lut)
    write_mem_16("exp_rom.mem", exp_lut)

    # ── 5. COMPUTE ───────────────────────────────────────────────────────────
    print("\n[STEP 5] Computing attention score (Phase 1)")
    score_int = compute_attention_score(Q_int, K_int, FRAC_BITS, SQRT_SHIFT, DATA_WIDTH)
    print(f"  Score range: [{score_int.min()}, {score_int.max()}]")

    print("\n[STEP 6] Computing softmax (Phase 2)")
    exp_Z, sum_exp, weights_int = compute_softmax(score_int, exp_lut, FRAC_BITS)

    # ── 6. WRITE FILES ───────────────────────────────────────────────────────
    print("\n[STEP 7] Writing output files")

    # Q, K, V — flatten row-major, 32-bit words (16-bit data zero-padded to 32)
    write_coe_32("q_ram.coe", Q_int.flatten())
    write_coe_32("k_ram.coe", K_int.flatten())
    write_coe_32("v_ram.coe", V_int.flatten())

    write_mem_32("q_ram.mem", Q_int.flatten())
    write_mem_32("k_ram.mem", K_int.flatten())
    write_mem_32("v_ram.mem", V_int.flatten())

    # golden_score.mem: SEQ_LEN × D_HEAD elements, 32-bit, row-major
    write_golden_score(score_int)

    # ── 7. REPORT ────────────────────────────────────────────────────────────
    label = "UNIFORM" if RUN_MODE == 1 else "RANDOM"
    print_report(Q_int, K_int, score_int, exp_Z, sum_exp, weights_int,
                 FRAC_BITS, SQRT_SHIFT, label=label)

    # ── 8. SUMMARY ───────────────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("  SUMMARY")
    print("=" * 70)
    print(f"  D_MODEL={D_MODEL}  SEQ_LEN={SEQ_LEN}  D_HEAD={D_HEAD}"
          f"  N_PE={N_PE}  DATA_WIDTH={DATA_WIDTH}")
    print(f"  FRAC_BITS={FRAC_BITS}  SQRT_SHIFT={SQRT_SHIFT}")
    print(f"  Q  : [{SEQ_LEN} × {D_MODEL}]  →  q_ram.mem  ({SEQ_LEN*D_MODEL} words)")
    print(f"  K  : [{D_HEAD}  × {D_MODEL}]  →  k_ram.mem  ({D_HEAD*D_MODEL} words)")
    print(f"  S  : [{SEQ_LEN} × {D_HEAD}]   →  golden_score.mem  ({SEQ_LEN*D_HEAD} words)")
    print(f"  Mode: {label}")
    print(f"  Files written to: {MEM_OUT_PATH}")
    print("=" * 70)