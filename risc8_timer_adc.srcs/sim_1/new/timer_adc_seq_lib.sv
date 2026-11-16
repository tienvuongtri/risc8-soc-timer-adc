// =============================================================================
// File: timer_adc_seq_lib.sv
// Description: UVM virtual sequence library containing helper tasks and
//              all 10 verification scenarios
// =============================================================================

class tadc_base_vseq extends uvm_sequence #(uvm_sequence_item);

    `uvm_object_utils(tadc_base_vseq)

    timer_adc_reg_block rm;
    apb_sequencer       apb_sqr;
    adc_sequencer       adc_sqr;
    virtual apb_if      apb_vif;
    virtual adc_if      adc_vif;

    function new(string name = "tadc_base_vseq");
        super.new(name);
    endfunction

    // Write an 8-bit register through the RAL model
    virtual task ral_write(uvm_reg rg, bit [7:0] val);
        uvm_status_e status;
        rg.write(status, val, .parent(this));
    endtask

    // Read an 8-bit register through the RAL model
    virtual task ral_read(uvm_reg rg, output bit [7:0] val);
        uvm_status_e   status;
        uvm_reg_data_t data;
        rg.read(status, data, .parent(this));
        val = data[7:0];
    endtask

    // Direct bus write via APB sequencer (useful for testing RO register writes)
    virtual task raw_write(bit [3:0] addr, bit [7:0] data);
        apb_item item = apb_item::type_id::create("raw_wr");
        start_item(item, -1, apb_sqr);
        item.pwrite = 1'b1;
        item.paddr  = addr;
        item.pwdata = data;
        finish_item(item);
    endtask

    // Direct bus read via APB sequencer
    virtual task raw_read(bit [3:0] addr, output bit [7:0] data);
        apb_item item = apb_item::type_id::create("raw_rd");
        start_item(item, -1, apb_sqr);
        item.pwrite = 1'b0;
        item.paddr  = addr;
        item.pwdata = 8'h00;
        finish_item(item);
        data = item.prdata;
    endtask

    // Drive all 4 analog input voltages via ADC agent
    virtual task set_all_voltages(real v0, real v1, real v2, real v3);
        adc_item item = adc_item::type_id::create("v_all");
        start_item(item, -1, adc_sqr);
        item.kind      = ADC_SET_VOLT;
        item.target_ch = -1;
        item.vin[0]    = v0;
        item.vin[1]    = v1;
        item.vin[2]    = v2;
        item.vin[3]    = v3;
        finish_item(item);
    endtask

    // Drive a single analog channel voltage via ADC agent
    virtual task set_ch_voltage(int ch, real v);
        adc_item item = adc_item::type_id::create("v_ch");
        start_item(item, -1, adc_sqr);
        item.kind      = ADC_SET_VOLT;
        item.target_ch = ch;
        item.vin[ch]   = v;
        finish_item(item);
    endtask

    // Configure analog offset and noise in LSBs
    virtual task set_impairments(real offset_v, real noise_lsb);
        adc_item item = adc_item::type_id::create("impair");
        start_item(item, -1, adc_sqr);
        item.kind      = ADC_SET_IMPAIR;
        item.offset_v  = offset_v;
        item.noise_lsb = noise_lsb;
        finish_item(item);
    endtask

    // Wait for N system clock cycles
    virtual task wait_cycles(int n);
        repeat (n) @(posedge apb_vif.clk);
    endtask

    // Poll ADC_STAT until BUSY bit [6] clears
    virtual task wait_adc_idle();
        bit [7:0] stat;
        int       guard = 0;
        do begin
            ral_read(rm.adc_stat, stat);
            guard++;
        end while ((stat[6] == 1'b1) && (guard < 200));
    endtask

    // Drain all queued entries from the FIFO
    virtual task drain_fifo();
        bit [7:0] stat;
        bit [7:0] dummy;
        int       i;
        ral_read(rm.adc_stat, stat);
        for (i = 0; i < stat[3:0]; i++) begin
            ral_read(rm.adc_data, dummy);
        end
    endtask

    // Clean peripheral state back to defaults between sub-sequences
    virtual task clean_peripheral_state();
        ral_write(rm.tmr_ctrl,   8'h00);
        ral_write(rm.adc_ctrl,   8'h00);
        ral_write(rm.tmr_presc,  8'h00);
        ral_write(rm.tmr_load,   8'hFF);
        ral_write(rm.tmr_cmp,    8'h80);
        ral_write(rm.adc_smp,    8'h04);
        ral_write(rm.adc_div,    8'h00);
        ral_write(rm.adc_thr_lo, 8'h00);
        ral_write(rm.adc_thr_hi, 8'hFF);
        ral_write(rm.irq_en,     8'h00);
        drain_fifo();
        ral_write(rm.irq_stat,   8'h3F);
    endtask

endclass

// =============================================================================
// 1. Register Test Sequence: reset values, bit-bash, RO protection
// =============================================================================
class tadc_reg_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_reg_seq)

    function new(string name = "tadc_reg_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] val;
        bit [7:0] pat[4] = '{8'h55, 8'hAA, 8'hFF, 8'h00};

        `uvm_info("SEQ", "Starting tadc_reg_seq...", UVM_LOW)

        // Read all 16 registers at reset
        ral_read(rm.tmr_ctrl,   val);
        ral_read(rm.tmr_presc,  val);
        ral_read(rm.tmr_load,   val);
        ral_read(rm.tmr_cmp,    val);
        ral_read(rm.tmr_cnt,    val);
        ral_read(rm.adc_ctrl,   val);
        ral_read(rm.adc_smp,    val);
        ral_read(rm.adc_div,    val);
        ral_read(rm.adc_thr_lo, val);
        ral_read(rm.adc_thr_hi, val);
        ral_read(rm.adc_data,   val);
        ral_read(rm.adc_rch,    val);
        ral_read(rm.adc_stat,   val);
        ral_read(rm.irq_en,     val);
        ral_read(rm.irq_stat,   val);
        ral_read(rm.id,         val);

        // Bit-bash RW configuration registers
        foreach (pat[i]) begin
            ral_write(rm.tmr_presc,  pat[i]); ral_read(rm.tmr_presc,  val);
            ral_write(rm.tmr_load,   pat[i]); ral_read(rm.tmr_load,   val);
            ral_write(rm.tmr_cmp,    pat[i]); ral_read(rm.tmr_cmp,    val);
            ral_write(rm.adc_smp,    pat[i]); ral_read(rm.adc_smp,    val);
            ral_write(rm.adc_div,    pat[i]); ral_read(rm.adc_div,    val);
            ral_write(rm.adc_thr_lo, pat[i]); ral_read(rm.adc_thr_lo, val);
            ral_write(rm.adc_thr_hi, pat[i]); ral_read(rm.adc_thr_hi, val);
            ral_write(rm.irq_en,     pat[i]); ral_read(rm.irq_en,     val);
        end

        // Verify RO registers ignore writes
        raw_write(4'h4, 8'hAB); // TMR_CNT
        ral_read(rm.tmr_cnt, val);
        raw_write(4'hF, 8'h12); // ID
        ral_read(rm.id, val);

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 2. Timer Test Sequence: 14 timer settings (periodic, one-shot, LOAD=0, etc.)
// =============================================================================
class tadc_timer_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_timer_seq)

    function new(string name = "tadc_timer_seq");
        super.new(name);
    endfunction

    virtual task run_timer_case(
        bit [7:0] presc,
        bit [7:0] load,
        bit [7:0] cmp,
        bit       oneshot,
        int       wait_clks
    );
        bit [7:0] val;
        ral_write(rm.tmr_ctrl,  8'h00);
        ral_write(rm.irq_stat,  8'h3F);
        ral_write(rm.tmr_presc, presc);
        ral_write(rm.tmr_load,  load);
        ral_write(rm.tmr_cmp,   cmp);
        ral_write(rm.irq_en,    8'h03);
        ral_write(rm.tmr_ctrl,  {6'b000000, oneshot, 1'b1});
        wait_cycles(wait_clks);
        ral_read(rm.tmr_cnt,  val);
        ral_read(rm.tmr_ctrl, val);
        ral_read(rm.irq_stat, val);
        ral_write(rm.tmr_ctrl, 8'h00);
        ral_write(rm.irq_stat, 8'h3F);
    endtask

    virtual task body();
        `uvm_info("SEQ", "Starting tadc_timer_seq (14 settings)...", UVM_LOW)

        // 1..4: Periodic mode with various PRESC, LOAD, CMP
        run_timer_case(8'd0,  8'd4,   8'd2,   1'b0, 20);
        run_timer_case(8'd1,  8'd5,   8'd3,   1'b0, 30);
        run_timer_case(8'd3,  8'd7,   8'd4,   1'b0, 40);
        run_timer_case(8'd8,  8'd3,   8'd1,   1'b0, 45);

        // 5..8: Corner cases: LOAD=0, CMP=0, CMP=LOAD, CMP>LOAD, max LOAD=255
        run_timer_case(8'd1,  8'd0,   8'd0,   1'b0, 12);
        run_timer_case(8'd0,  8'd9,   8'd0,   1'b0, 15);
        run_timer_case(8'd0,  8'd9,   8'd9,   1'b0, 15);
        run_timer_case(8'd0,  8'd16,  8'd128, 1'b0, 25);

        // 9..14: One-shot mode across prescaler bins (div1, small_p, large_p)
        run_timer_case(8'd0,  8'd3,   8'd1,   1'b1, 12);
        run_timer_case(8'd1,  8'd4,   8'd2,   1'b1, 20);
        run_timer_case(8'd2,  8'd3,   8'd1,   1'b1, 20);
        run_timer_case(8'd8,  8'd2,   8'd1,   1'b1, 35);
        run_timer_case(8'd0,  8'd255, 8'd200, 1'b0, 20);
        run_timer_case(8'd0,  8'd1,   8'd0,   1'b1, 10);

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 3. Software-Triggered ADC Sequence: corners, channels 0..3, SMP/DIV bins
// =============================================================================
class tadc_adc_sw_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_adc_sw_seq)

    function new(string name = "tadc_adc_sw_seq");
        super.new(name);
    endfunction

    virtual task convert_and_read(bit [1:0] ch, bit [7:0] smp, bit [7:0] div);
        bit [7:0] rch, data, stat;
        ral_write(rm.adc_smp,  smp);
        ral_write(rm.adc_div,  div);
        ral_write(rm.adc_ctrl, {2'b00, ch, 2'b00, 1'b1, 1'b1}); // EN=1, START=1
        wait_adc_idle();
        ral_read(rm.adc_stat, stat);
        ral_read(rm.adc_rch,  rch);
        ral_read(rm.adc_data, data);
        ral_write(rm.irq_stat, 8'h04); // Clear ADC_EOC
    endtask

    virtual task body();
        real corners[6] = '{0.0, 0.400, 1.111, 2.000, 3.000, 3.300};
        int  c, ch;

        `uvm_info("SEQ", "Starting tadc_adc_sw_seq...", UVM_LOW)
        clean_peripheral_state();

        // Sweep corner voltages across all 4 channels and SMP/DIV speed bins
        foreach (corners[c]) begin
            set_all_voltages(corners[c], corners[c], corners[c], corners[c]);
            for (ch = 0; ch < 4; ch++) begin
                convert_and_read(ch[1:0], 8'd1, 8'd0);
            end
        end

        // Exercise medium and slow SMP/DIV bins for coverage
        set_all_voltages(0.400, 1.111, 2.000, 3.000);
        convert_and_read(2'd0, 8'd4, 8'd1);
        convert_and_read(2'd1, 8'd8, 8'd0);
        convert_and_read(2'd2, 8'd2, 8'd4);
        convert_and_read(2'd3, 8'd5, 8'd2);

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 4. Timer-Triggered ADC Sequence: overflow & compare triggers on ramping inputs
// =============================================================================
class tadc_adc_timer_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_adc_timer_seq)

    function new(string name = "tadc_adc_timer_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] stat, rch, data;
        int       ch, step;
        real      v;

        `uvm_info("SEQ", "Starting tadc_adc_timer_seq...", UVM_LOW)
        clean_peripheral_state();

        ral_write(rm.adc_smp,   8'd1);
        ral_write(rm.adc_div,   8'd0);
        ral_write(rm.tmr_presc, 8'd1);
        ral_write(rm.tmr_load,  8'd9); // Period = 20 clocks
        ral_write(rm.tmr_cmp,   8'd4);

        // Test both TRIG_SEL=1 (tmr_ovf) and TRIG_SEL=2 (tmr_cmp) across CH0..CH3
        for (ch = 0; ch < 4; ch++) begin
            for (step = 0; step < 2; step++) begin
                v = 0.25 + (ch * 0.75) + (step * 0.20);
                set_ch_voltage(ch, v);

                // TRIG_SEL = 1 (timer overflow)
                ral_write(rm.adc_ctrl, {2'b00, ch[1:0], 2'b01, 1'b0, 1'b1});
                ral_write(rm.tmr_ctrl, 8'h03); // One-shot timer
                wait_cycles(35);
                ral_read(rm.adc_stat, stat);
                ral_read(rm.adc_rch,  rch);
                ral_read(rm.adc_data, data);

                // TRIG_SEL = 2 (timer compare)
                ral_write(rm.adc_ctrl, {2'b00, ch[1:0], 2'b10, 1'b0, 1'b1});
                ral_write(rm.tmr_ctrl, 8'h03); // One-shot timer
                wait_cycles(35);
                ral_read(rm.adc_stat, stat);
                ral_read(rm.adc_rch,  rch);
                ral_read(rm.adc_data, data);
            end
        end

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 5. Continuous ADC & FIFO Overflow / Abort / W1C Race Sequence
// =============================================================================
class tadc_adc_cont_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_adc_cont_seq)

    function new(string name = "tadc_adc_cont_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] stat, data;
        int       ch, i;

        `uvm_info("SEQ", "Starting tadc_adc_cont_seq...", UVM_LOW)
        clean_peripheral_state();
        set_all_voltages(0.400, 1.111, 2.000, 3.000);

        ral_write(rm.adc_smp, 8'd1);
        ral_write(rm.adc_div, 8'd0);

        // Exercise continuous mode (TRIG_SEL=3) across all 4 channels
        for (ch = 0; ch < 4; ch++) begin
            ral_write(rm.adc_ctrl, {2'b00, ch[1:0], 2'b11, 1'b0, 1'b1});
            wait_cycles(25);
            ral_write(rm.adc_ctrl, 8'h00); // Abort mid-conversion
            drain_fifo();
        end

        // Let continuous mode fill all 8 FIFO slots and overflow
        ral_write(rm.irq_stat, 8'h3F);
        ral_write(rm.irq_en,   8'h14); // Enable FIFO_OVR and ADC_EOC
        ral_write(rm.adc_ctrl, 8'h1D); // EN=1, TRIG_SEL=3 (cont), CH=1
        wait_cycles(120);              // > 10 conversions -> FIFO full + overflow

        // Test W1C race while continuous conversions are still firing
        ral_write(rm.irq_stat, 8'h04);
        wait_cycles(15);

        // Stop ADC and inspect full FIFO & overflow flag
        ral_write(rm.adc_ctrl, 8'h00);
        ral_read(rm.adc_stat,  stat);
        ral_read(rm.irq_stat,  stat);

        // Pop FIFO step-by-step to sample all FIFO level bins (8 down to 0)
        for (i = 0; i < 8; i++) begin
            ral_read(rm.adc_stat, stat);
            ral_read(rm.adc_data, data);
        end
        ral_read(rm.adc_stat, stat);

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 6. Window Comparator Sequence: below low, inside window, above high, boundaries
// =============================================================================
class tadc_window_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_window_seq)

    function new(string name = "tadc_window_seq");
        super.new(name);
    endfunction

    virtual task body();
        real      test_v[3] = '{0.250, 1.500, 2.900}; // Below, Inside, Above
        bit [7:0] stat, data;
        int       ch, z;

        `uvm_info("SEQ", "Starting tadc_window_seq...", UVM_LOW)
        clean_peripheral_state();

        ral_write(rm.adc_smp,    8'd1);
        ral_write(rm.adc_div,    8'd0);
        ral_write(rm.adc_thr_lo, 8'd50);  // ~0.645 V
        ral_write(rm.adc_thr_hi, 8'd180); // ~2.320 V
        ral_write(rm.irq_en,     8'h08);  // Enable ADC_WD interrupt

        // Sweep all 4 channels across all 3 window zones (below, inside, above)
        for (ch = 0; ch < 4; ch++) begin
            for (z = 0; z < 3; z++) begin
                ral_write(rm.irq_stat, 8'h3F);
                set_ch_voltage(ch, test_v[z]);
                ral_write(rm.adc_ctrl, {2'b00, ch[1:0], 2'b00, 1'b1, 1'b1});
                wait_adc_idle();
                ral_read(rm.irq_stat, stat);
                ral_read(rm.adc_data, data);
                ral_write(rm.irq_stat, 8'h3F);
            end
        end

        // Exact boundary code checks: code == 50 (in window) and code == 49 (below)
        set_ch_voltage(0, (50.5 / 256.0) * 3.3);
        ral_write(rm.adc_ctrl, 8'h03);
        wait_adc_idle();
        ral_read(rm.irq_stat, stat);
        ral_read(rm.adc_data, data);

        set_ch_voltage(0, (49.5 / 256.0) * 3.3);
        ral_write(rm.adc_ctrl, 8'h03);
        wait_adc_idle();
        ral_read(rm.irq_stat, stat);
        ral_read(rm.adc_data, data);

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 7. Analog Noise & Offset Sequence
// =============================================================================
class tadc_noise_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_noise_seq)

    function new(string name = "tadc_noise_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] data;
        int       ch, k;

        `uvm_info("SEQ", "Starting tadc_noise_seq...", UVM_LOW)
        clean_peripheral_state();
        set_all_voltages(0.400, 1.111, 2.000, 3.000);

        // Inject +10 mV offset and 1.5 LSB uniform random noise
        set_impairments(0.010, 1.5);
        ral_write(rm.adc_smp, 8'd2);
        ral_write(rm.adc_div, 8'd0);

        for (k = 0; k < 4; k++) begin
            for (ch = 0; ch < 4; ch++) begin
                ral_write(rm.adc_ctrl, {2'b00, ch[1:0], 2'b00, 1'b1, 1'b1});
                wait_adc_idle();
                ral_read(rm.adc_data, data);
            end
        end

        // Restore ideal analog front-end behavior
        set_impairments(0.0, 0.0);
        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 8. Trigger Miss Sequence: triggers arriving faster than conversion time
// =============================================================================
class tadc_trig_miss_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_trig_miss_seq)

    function new(string name = "tadc_trig_miss_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] stat, data;

        `uvm_info("SEQ", "Starting tadc_trig_miss_seq...", UVM_LOW)
        clean_peripheral_state();
        set_all_voltages(0.400, 1.111, 2.000, 3.000);

        // Configure slow ADC conversion: (5 + 1 + 8) * (1 + 1) = 28 clocks
        ral_write(rm.adc_smp,  8'd5);
        ral_write(rm.adc_div,  8'd1);
        ral_write(rm.irq_en,   8'h20); // Enable TRIG_MISS interrupt
        ral_write(rm.irq_stat, 8'h3F);

        // Case A: Software trigger issued while ADC is already converting
        ral_write(rm.adc_ctrl, 8'h03); // Start 1st conversion
        ral_write(rm.adc_ctrl, 8'h03); // 2nd start while busy -> sets TRIG_MISS
        wait_adc_idle();
        ral_read(rm.irq_stat, stat);
        ral_read(rm.adc_data, data);
        ral_write(rm.irq_stat, 8'h3F);

        // Case B: Fast periodic timer overflow triggers (every 6 clocks)
        ral_write(rm.tmr_presc, 8'd0);
        ral_write(rm.tmr_load,  8'd5);
        ral_write(rm.adc_ctrl,  8'h15); // EN=1, TRIG_SEL=1 (tmr_ovf), CH=1
        ral_write(rm.tmr_ctrl,  8'h01); // Start fast periodic timer
        wait_cycles(45);
        ral_write(rm.tmr_ctrl,  8'h00);
        ral_write(rm.adc_ctrl,  8'h00);
        ral_read(rm.irq_stat,   stat);

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 9. Random Stimulus Sequence
// =============================================================================
class tadc_random_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_random_seq)

    function new(string name = "tadc_random_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] rch, data, stat;
        int       iter;
        bit [1:0] rand_ch;
        bit [7:0] rand_smp, rand_div;
        real      v0, v1, v2, v3;

        `uvm_info("SEQ", "Starting tadc_random_seq...", UVM_LOW)
        clean_peripheral_state();

        for (iter = 0; iter < 16; iter++) begin
            v0 = ($urandom_range(0, 3300)) / 1000.0;
            v1 = ($urandom_range(0, 3300)) / 1000.0;
            v2 = ($urandom_range(0, 3300)) / 1000.0;
            v3 = ($urandom_range(0, 3300)) / 1000.0;
            set_all_voltages(v0, v1, v2, v3);

            rand_ch  = $urandom_range(0, 3);
            rand_smp = $urandom_range(0, 6);
            rand_div = $urandom_range(0, 2);

            ral_write(rm.adc_smp,  rand_smp);
            ral_write(rm.adc_div,  rand_div);
            ral_write(rm.adc_ctrl, {2'b00, rand_ch, 2'b00, 1'b1, 1'b1});
            wait_adc_idle();
            ral_read(rm.adc_stat, stat);
            ral_read(rm.adc_rch,  rch);
            ral_read(rm.adc_data, data);
        end

        clean_peripheral_state();
    endtask

endclass

// =============================================================================
// 10. All-in-One Regression Sequence (runs all 9 sequences above in order)
// =============================================================================
class tadc_all_seq extends tadc_base_vseq;

    `uvm_object_utils(tadc_all_seq)

    function new(string name = "tadc_all_seq");
        super.new(name);
    endfunction

    virtual task run_subseq(tadc_base_vseq sub);
        sub.rm      = this.rm;
        sub.apb_sqr = this.apb_sqr;
        sub.adc_sqr = this.adc_sqr;
        sub.apb_vif = this.apb_vif;
        sub.adc_vif = this.adc_vif;
        sub.start(null, this);
    endtask

    virtual task body();
        tadc_reg_seq       s_reg   = tadc_reg_seq::type_id::create("s_reg");
        tadc_timer_seq     s_tmr   = tadc_timer_seq::type_id::create("s_tmr");
        tadc_adc_sw_seq    s_sw    = tadc_adc_sw_seq::type_id::create("s_sw");
        tadc_adc_timer_seq s_atmr  = tadc_adc_timer_seq::type_id::create("s_atmr");
        tadc_adc_cont_seq  s_cont  = tadc_adc_cont_seq::type_id::create("s_cont");
        tadc_window_seq    s_win   = tadc_window_seq::type_id::create("s_win");
        tadc_noise_seq     s_noise = tadc_noise_seq::type_id::create("s_noise");
        tadc_trig_miss_seq s_miss  = tadc_trig_miss_seq::type_id::create("s_miss");
        tadc_random_seq    s_rand  = tadc_random_seq::type_id::create("s_rand");

        `uvm_info("SEQ", "=== Starting tadc_all_seq (Full Suite) ===", UVM_LOW)
        run_subseq(s_reg);
        run_subseq(s_tmr);
        run_subseq(s_sw);
        run_subseq(s_atmr);
        run_subseq(s_cont);
        run_subseq(s_win);
        run_subseq(s_noise);
        run_subseq(s_miss);
        run_subseq(s_rand);
        `uvm_info("SEQ", "=== Completed tadc_all_seq ===", UVM_LOW)
    endtask

endclass