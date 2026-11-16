# 8-Bit 5-Stage Pipelined RISC SoC with Timer, SAR ADC & UVM 1.2 Verification

An 8-bit Harvard RISC System-on-Chip (`risc8_soc`) featuring a 5-stage pipelined processor core integrated with a memory-mapped 8-bit Timer/PWM and 4-channel 8-bit Successive Approximation Register (SAR) ADC peripheral. The design is verified using a complete **UVM 1.2** verification environment, **30 SystemVerilog Assertions (SVA)**, and full-system firmware simulation, and is implemented on an **AMD/Xilinx Artix-7 FPGA (`xc7a35tcpg236-1`)** using Vivado 2026.1.

---

## 1. System Architecture Overview

The SoC integrates two primary subsystems across a single-cycle memory-mapped I/O bus (`0xF0`–`0xFF`):

1. **`risc8_5stage_core` (8-Bit 5-Stage Pipelined RISC CPU):**
   - **Harvard Architecture:** Separate $256 \times 16$-bit Instruction ROM (`imem`) and $256 \times 8$-bit Data RAM (`dmem`).
   - **5 Pipeline Stages:** Instruction Fetch (`IF`) $\rightarrow$ Instruction Decode (`ID`) $\rightarrow$ Execute (`EX`) $\rightarrow$ Memory Access (`MEM`) $\rightarrow$ Write-Back (`WB`).
   - **Register File:** Eight 8-bit general-purpose registers (`R0`–`R7`, where `R0` is fully writable) with asynchronous dual-read ports, synchronous write port, and internal `WB-to-ID` write-through bypass.
   - **Hazard Detection & Forwarding (`hazard_unit`):**
     - **Data Hazards:** Full operand forwarding from `EX/MEM` (`2'b10`) and `MEM/WB` (`2'b01`) to `EX`, gated by operand usage (`uses_a`, `uses_b`).
     - **Load-Use Hazard:** Automatic 1-cycle pipeline stall (freezes `PC` and `IF/ID`, inserts a bubble into `ID/EX`).
     - **Control Hazards:** Branches and jumps (`JMP`, `BZ`, `BNZ`) resolved in `EX` using architectural flags `{Z, C}` with a 2-cycle flush of younger instructions on taken branches.
   - **Memory-Mapped I/O Decode (Stage 4 `MEM`):** Maps addresses `0xF0`–`0xFF` (`IO_PAGE = 4'hF`) to the external `io_*` bus while keeping `0x00`–`0xEF` (240 bytes) as Data RAM. `io_cs` is strictly gated with valid `LD`/`ST` operations (`(exmem_mem_we || exmem_mem_to_reg) && !halted`) so ALU pointer arithmetic on I/O addresses never triggers false FIFO pops.

2. **`timer_adc8_cpu_if` & `timer_adc8_top` (Timer + SAR ADC + FIFO Peripheral):**
   - **`timer8` (8-Bit Timer & PWM):** 8-bit programmable prescaler (`TMR_PRESC`), period reload (`TMR_LOAD`), compare match (`TMR_CMP`), periodic and auto-stopping one-shot modes, overflow/compare trigger pulses, and hardware PWM output:
     $$\text{Period} = (\text{PRESC} + 1) \times (\text{LOAD} + 1) \text{ clocks}, \quad \text{PWM Duty} = \frac{\text{CMP}}{\text{LOAD} + 1}$$
   - **`sar_adc_ctrl` (8-Bit 4-Channel SAR ADC Controller):** 4-state FSM (`ST_IDLE`, `ST_SAMPLE`, `ST_CONVERT`, `ST_DONE`) performing 8-bit binary search from MSB (bit 7) down to LSB (bit 0) across 4 analog channels (`CH0`–`CH3`, $V_{\text{ref}} = 3.3\text{ V}$, $1\text{ LSB} = 12.891\text{ mV}$):
     $$\text{Conversion Time} = (\text{SMP} + 1 + 8) \times (\text{DIV} + 1) \text{ clocks}$$
   - **`sync_fifo` (8-Entry Synchronous Result Queue):** Buffers up to 8 completed conversions as `{ch[1:0], data[7:0]}` pairs. Reading `ADC_DATA` (`0xFA`) pops the oldest entry; reading `ADC_RCH` (`0xFB`) inspects the channel and validity without popping.
   - **`apb_regs8` (16 Registers & Interrupt Controller):** Supports 4 ADC trigger modes (Software `START`, Timer Overflow, Timer Compare, Continuous), digital window watchdog thresholds (`ADC_THR_LO`, `ADC_THR_HI`), and 6 sticky Write-1-to-Clear (`W1C`) interrupt flags with hardware-set priority over software clear.

---

## 2. Instruction Set Architecture (ISA)

All instructions are 16 bits wide with a 4-bit opcode (`instr[15:12]`):

| Opcode | Mnemonic | Format | Operation | Flags Affected |
| :--- | :--- | :--- | :--- | :--- |
| `0x0` | `NOP` | — | No operation | — |
| `0x1` | `ADD rd, rs1, rs2` | R | `rd = rs1 + rs2` | `Z, C` |
| `0x2` | `SUB rd, rs1, rs2` | R | `rd = rs1 - rs2` (`C = 1` on borrow) | `Z, C` |
| `0x3` | `AND rd, rs1, rs2` | R | `rd = rs1 & rs2` | `Z, C=0` |
| `0x4` | `OR  rd, rs1, rs2` | R | `rd = rs1 \| rs2` | `Z, C=0` |
| `0x5` | `XOR rd, rs1, rs2` | R | `rd = rs1 ^ rs2` | `Z, C=0` |
| `0x6` | `SHL rd, rs1` | R1 | `rd = rs1 << 1` (`C = rs1[7]`) | `Z, C` |
| `0x7` | `SHR rd, rs1` | R1 | `rd = rs1 >> 1` (`C = rs1[0]`) | `Z, C` |
| `0x8` | `LDI rd, imm8` | I | `rd = imm8` | — |
| `0x9` | `ADDI rd, imm8` | I | `rd = rd + imm8` | `Z, C` |
| `0xA` | `LD  rd, [rs1]` | R1 | `rd = MEM[rs1]` | — |
| `0xB` | `ST  rd, [rs1]` | R1 | `MEM[rs1] = rd` | — |
| `0xC` | `JMP addr8` | J | `PC = addr8` | — |
| `0xD` | `BZ  addr8` | J | `if (Z == 1) PC = addr8` | — |
| `0xE` | `BNZ addr8` | J | `if (Z == 0) PC = addr8` | — |
| `0xF` | `HLT` | — | Stop instruction fetch and halt pipeline at WB | — |

---

## 3. Peripheral Register Map (`0xF0`–`0xFF`)

| Offset | CPU Address | Name | Access | Reset | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `0x0` | `0xF0` | `TMR_CTRL` | RW | `0x00` | `[1]` ONESHOT, `[0]` EN (auto-clears on one-shot overflow) |
| `0x1` | `0xF1` | `TMR_PRESC` | RW | `0x00` | Prescaler divider: tick every `PRESC + 1` clocks |
| `0x2` | `0xF2` | `TMR_LOAD` | RW | `0xFF` | Timer terminal count (`Period - 1` ticks) |
| `0x3` | `0xF3` | `TMR_CMP` | RW | `0x80` | Timer compare value / PWM high threshold |
| `0x4` | `0xF4` | `TMR_CNT` | RO | `0x00` | Current 8-bit timer counter value |
| `0x5` | `0xF5` | `ADC_CTRL` | RW | `0x00` | `[5:4]` CH, `[3:2]` TRIG_SEL, `[1]` START (self-clearing), `[0]` EN |
| `0x6` | `0xF6` | `ADC_SMP` | RW | `0x04` | Sample-and-hold duration (`SMP + 1` ADC ticks) |
| `0x7` | `0xF7` | `ADC_DIV` | RW | `0x00` | ADC clock divider (`DIV + 1` system clocks per ADC tick) |
| `0x8` | `0xF8` | `ADC_THR_LO` | RW | `0x00` | Window comparator lower threshold |
| `0x9` | `0xF9` | `ADC_THR_HI` | RW | `0xFF` | Window comparator upper threshold |
| `0xA` | `0xFA` | `ADC_DATA` | RO (Pop)| `0x00` | Oldest 8-bit ADC conversion result (reading pops 1 FIFO entry) |
| `0xB` | `0xFB` | `ADC_RCH` | RO | `0x00` | `[7]` VALID (`!EMPTY`), `[1:0]` Channel of oldest FIFO entry (no pop) |
| `0xC` | `0xFC` | `ADC_STAT` | RO | `0x10` | `[6]` BUSY, `[5]` FULL, `[4]` EMPTY, `[3]`..`[0]` FIFO LEVEL (`0..8`) |
| `0xD` | `0xFD` | `IRQ_EN` | RW | `0x00` | Interrupt enable mask for `[5:0]` events |
| `0xE` | `0xFE` | `IRQ_STAT` | W1C | `0x00` | `[5]` TRIG_MISS, `[4]` FIFO_OVR, `[3]` ADC_WD, `[2]` ADC_EOC, `[1]` TMR_CMP, `[0]` TMR_OVF |
| `0xF` | `0xFF` | `ID` | RO | `0xA8` | Peripheral identification constant (`0xA8`) |

---

## 4. Verification Methodology & Simulation Results

The project employs a multi-layered verification strategy:

### 4.1 UVM 1.2 Verification Environment (`tb_top.sv`)
- **Agents:** Active `apb_agent` (`apb_driver`, `apb_monitor`, `apb_sequencer`) and Active `adc_agent` (`adc_driver`, `adc_monitor`) driving real-valued voltages, DC offset (`offset_v`), and uniform random noise (`noise_lsb`) into `sar_afe_model.sv`.
- **UVM RAL:** Complete 16-register abstraction model (`timer_adc_ral.sv`) with `reg2apb_adapter` and explicit `uvm_reg_predictor`.
- **Scoreboard (`timer_adc_scoreboard.sv`):** Golden reference FIFO, ideal SAR transfer-function predictor ($\lfloor V_{\text{hold}} / V_{\text{ref}} \times 256 \rfloor$), noise tolerance checker, and shadow register file.
- **30 SystemVerilog Assertions (`timer_adc_sva.sv`):** Bound into `timer_adc8_top` via `bind`, checking Timer invariants, SAR ADC FSM timing, FIFO pointers/levels, and APB/W1C interrupt rules on every clock edge.
- **10 UVM Tests (`timer_adc_tests.sv`):** `tadc_reg_test`, `tadc_timer_test`, `tadc_adc_sw_test`, `tadc_adc_timer_test`, `tadc_adc_cont_test`, `tadc_window_test`, `tadc_noise_test`, `tadc_trig_miss_test`, `tadc_random_test`, and the full regression suite `tadc_all_test`.

### 4.2 Summary of Verification Runs (Vivado XSim 2026.1)

| Testbench | Scope | Result | Key Metrics |
| :--- | :--- | :--- | :--- |
| `tb_risc8_5stage.v` | Standalone 5-Stage CPU | **PASS (10/10 checks)** | 51 cycles, 34 retired instructions, **CPI = 1.50** |
| `tb_directed.sv` | APB Peripheral + 30 SVA | **PASS (37/37 checks)** | Reset, RO protection, Timer, SAR ADC, Window, FIFO OVR, 0 SVA errors |
| `tb_cpu_if.sv` | 1-Cycle CPU Wrapper + SVA | **PASS (20/20 checks)** | Single-cycle LD/ST, CH0–CH3 conversions, One-shot, W1C IRQ, FIFO drain |
| `tb_risc8_soc.v` | Full SoC (`soc_demo.mem`) | **PASS (22/22 checks)** | 645 cycles, 122 I/O accesses, ALU pointer safety test, 30% PWM duty |
| `tb_top.sv` (`tadc_all_test`) | Full UVM 1.2 Suite + SVA | **PASS (0 UVM_ERROR)** | 112 conversions, 683 FIFO reads, 789 reg reads, 109 timer events, **100.0% Functional Coverage** (all 5 covergroups) |

---

## 5. FPGA Synthesis & Implementation Results

Synthesized and implemented on **AMD/Xilinx Vivado 2026.1** targeting the **Artix-7 (`xc7a35tcpg236-1`)** FPGA with a `100 MHz` (`10.000 ns`) system clock constraint:

### 5.1 Resource Utilization (`risc8_soc`)

| Hierarchy Module | Slice LUTs (20,800) | Logic LUTs (20,800) | LUTRAM (9,600) | Slice Registers (41,600) | F7 Muxes | F8 Muxes | Bonded IOBs (106) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`risc8_soc` (Top)** | **495 (2.38%)** | **463 (2.23%)** | **32 (0.33%)** | **408 (0.98%)** | **33** | **8** | **25 (23.58%)** |
| ├─ `u_cpu` (`risc8_5stage_core`) | 308 | 276 | 32 (`dmem`) | 182 | 29 | 8 | 0 |
| └─ `u_tadc` (`timer_adc8_cpu_if`) | 188 | 188 | 0 | 226 | 4 | 0 | 0 |

### 5.2 Timing Summary (`100 MHz` Clock Constraint)

- **Worst Negative Slack (WNS - Setup):** `+3.832 ns` (0 failing endpoints out of 1,487 paths $\rightarrow$ Maximum frequency $F_{\max} \approx 162.1\text{ MHz}$)
- **Worst Hold Slack (WHS - Hold):** `+0.081 ns` (0 failing endpoints)
- **Worst Pulse Width Slack (WPWS):** `+3.750 ns` (0 failing endpoints)

---

## 6. Repository Structure

    risc8_timer_adc/
    ├── risc8_timer_adc.xpr                  # Vivado 2026.1 project file
    ├── tb_top_behav.wcfg                    # UVM testbench waveform configuration
    ├── tb_risc8_soc_behav.wcfg              # Full SoC waveform configuration
    ├── tb_cpu_if_behav.wcfg                 # CPU wrapper waveform configuration
    ├── tb_directed_behav1.wcfg              # Directed APB waveform configuration
    ├── tb_risc8_5stage_behav.wcfg           # Standalone CPU waveform configuration
    └── risc8_timer_adc.srcs/
        ├── sources_1/new/                   # Synthesizable RTL & Memory Initialization
        │   ├── risc8_soc.v                  # SoC top-level module (CPU + Timer/ADC peripheral)
        │   ├── risc8_5stage_core.v          # 8-bit 5-stage pipelined RISC CPU core
        │   ├── alu.v                        # 8-bit ALU (ADD, SUB, AND, OR, XOR, SHL, SHR, LDI)
        │   ├── control_unit.v               # Hard-wired instruction decoder
        │   ├── regfile.v                    # 8x8-bit register file with WB-to-ID bypass
        │   ├── hazard_unit.v                # Forwarding & load-use stall controller
        │   ├── imem.v                       # 256x16-bit instruction ROM
        │   ├── dmem.v                       # 256x8-bit data RAM
        │   ├── timer_adc8_cpu_if.v          # 1-cycle CPU bus to APB wrapper
        │   ├── timer_adc8_top.v             # Timer + SAR ADC + FIFO peripheral top
        │   ├── apb_regs8.v                  # 16 APB registers & W1C interrupt controller
        │   ├── timer8.v                     # 8-bit prescaled timer & PWM generator
        │   ├── sar_adc_ctrl.v               # 8-bit SAR ADC state machine
        │   ├── sync_fifo.v                  # 8-entry synchronous result FIFO
        │   └── soc_demo.mem                 # Assembled firmware image for SoC verification
        ├── constrs_1/new/
        │   └── risc8.xdc                    # 100 MHz clock & I/O timing constraints
        └── sim_1/new/                       # Testbenches, SVA, AFE Models & UVM 1.2 Package
            ├── apb_if.sv                    # APB SystemVerilog interface & protocol assertion
            ├── adc_if.sv                    # Analog & event observation interface
            ├── sar_afe_model.sv             # Behavioral SAR Analog Front-End (with noise/offset)
            ├── afe_model.v                  # Verilog-2001 AFE model for SoC simulation
            ├── timer_adc_sva.sv             # 30 SVA properties + bind wrapper
            ├── timer_adc_pkg.sv             # UVM package including agents, RAL, SB, cov, seqs, tests
            ├── apb_agent.sv                 # UVM APB agent
            ├── adc_agent.sv                 # UVM Analog & event agent
            ├── timer_adc_ral.sv             # UVM Register Abstraction Layer (RAL)
            ├── timer_adc_scoreboard.sv      # UVM Scoreboard & golden predictor
            ├── timer_adc_coverage.sv        # 5 Functional Coverage groups
            ├── timer_adc_env.sv             # UVM Environment
            ├── timer_adc_seq_lib.sv         # 10 UVM virtual sequences
            ├── timer_adc_tests.sv           # 10 UVM test classes
            ├── tb_top.sv                    # UVM top-level testbench
            ├── tb_risc8_soc.v               # Full SoC testbench (22 checks)
            ├── tb_cpu_if.sv                 # CPU wrapper testbench (20 checks)
            ├── tb_directed.sv               # Directed APB testbench (37 checks)
            └── tb_risc8_5stage.v            # Standalone CPU core testbench (10 checks)

---

## 7. Running Simulations in Vivado

1. Open `risc8_timer_adc.xpr` in **Vivado**.
2. In the **Sources -> Simulation Sources (`sim_1`)** pane, right-click the desired testbench (`tb_risc8_soc`, `tb_top`, `tb_cpu_if`, `tb_directed`, or `tb_risc8_5stage`) and select **Set as Top**.
3. For UVM simulation (`tb_top`), ensure the UVM library is linked via the Tcl Console:

       set_property -name {xsim.compile.xvlog.more_options} -value {-L uvm} -objects [get_filesets sim_1]
       set_property -name {xsim.elaborate.xelab.more_options} -value {-L uvm} -objects [get_filesets sim_1]

4. Click **Run Simulation -> Run Behavioral Simulation**, then execute `run all` in the Tcl Console.
