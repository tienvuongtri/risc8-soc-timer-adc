// =============================================================================
// File: timer_adc_tests.sv
// Description: Base UVM test and 10 runnable test classes
// =============================================================================

class tadc_base_test extends uvm_test;

    `uvm_component_utils(tadc_base_test)

    timer_adc_env  m_env;
    virtual apb_if apb_vif;
    virtual adc_if adc_vif;

    function new(string name = "tadc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_env = timer_adc_env::type_id::create("m_env", this);

        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", apb_vif)) begin
            `uvm_fatal("TEST", "Could not retrieve apb_if from uvm_config_db")
        end
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", adc_vif)) begin
            `uvm_fatal("TEST", "Could not retrieve adc_if from uvm_config_db")
        end

        uvm_top.set_timeout(10ms, 1);
    endfunction

    virtual function void init_vseq(tadc_base_vseq vseq);
        vseq.rm      = m_env.rm;
        vseq.apb_sqr = m_env.m_apb_agent.sqr;
        vseq.adc_sqr = m_env.m_adc_agent.sqr;
        vseq.apb_vif = this.apb_vif;
        vseq.adc_vif = this.adc_vif;
    endfunction

endclass

// 1. Register test
class tadc_reg_test extends tadc_base_test;
    `uvm_component_utils(tadc_reg_test)
    function new(string name = "tadc_reg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_reg_seq seq = tadc_reg_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 2. Timer test
class tadc_timer_test extends tadc_base_test;
    `uvm_component_utils(tadc_timer_test)
    function new(string name = "tadc_timer_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_timer_seq seq = tadc_timer_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 3. Software-triggered ADC test
class tadc_adc_sw_test extends tadc_base_test;
    `uvm_component_utils(tadc_adc_sw_test)
    function new(string name = "tadc_adc_sw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_adc_sw_seq seq = tadc_adc_sw_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 4. Timer-triggered ADC test
class tadc_adc_timer_test extends tadc_base_test;
    `uvm_component_utils(tadc_adc_timer_test)
    function new(string name = "tadc_adc_timer_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_adc_timer_seq seq = tadc_adc_timer_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 5. Continuous ADC & FIFO overflow test
class tadc_adc_cont_test extends tadc_base_test;
    `uvm_component_utils(tadc_adc_cont_test)
    function new(string name = "tadc_adc_cont_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_adc_cont_seq seq = tadc_adc_cont_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 6. Window comparator test
class tadc_window_test extends tadc_base_test;
    `uvm_component_utils(tadc_window_test)
    function new(string name = "tadc_window_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_window_seq seq = tadc_window_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 7. Analog noise & offset test
class tadc_noise_test extends tadc_base_test;
    `uvm_component_utils(tadc_noise_test)
    function new(string name = "tadc_noise_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_noise_seq seq = tadc_noise_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 8. Trigger miss test
class tadc_trig_miss_test extends tadc_base_test;
    `uvm_component_utils(tadc_trig_miss_test)
    function new(string name = "tadc_trig_miss_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_trig_miss_seq seq = tadc_trig_miss_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 9. Random test
class tadc_random_test extends tadc_base_test;
    `uvm_component_utils(tadc_random_test)
    function new(string name = "tadc_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_random_seq seq = tadc_random_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass

// 10. Full regression test (runs all 9 tests back-to-back)
class tadc_all_test extends tadc_base_test;
    `uvm_component_utils(tadc_all_test)
    function new(string name = "tadc_all_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual task run_phase(uvm_phase phase);
        tadc_all_seq seq = tadc_all_seq::type_id::create("seq");
        phase.raise_objection(this);
        init_vseq(seq);
        seq.start(null);
        phase.drop_objection(this);
    endtask
endclass