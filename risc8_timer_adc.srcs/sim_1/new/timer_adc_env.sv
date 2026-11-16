// =============================================================================
// File: timer_adc_env.sv
// Description: UVM Environment connecting agents, RAL model, predictor,
//              scoreboard, and functional coverage collector
// =============================================================================

class timer_adc_env extends uvm_env;

    `uvm_component_utils(timer_adc_env)

    apb_agent                     m_apb_agent;
    adc_agent                     m_adc_agent;
    timer_adc_reg_block           rm;
    reg2apb_adapter               m_adapter;
    uvm_reg_predictor #(apb_item) m_predictor;
    timer_adc_scoreboard          m_sb;
    timer_adc_coverage            m_cov;

    function new(string name = "timer_adc_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        m_apb_agent = apb_agent::type_id::create("m_apb_agent", this);
        m_adc_agent = adc_agent::type_id::create("m_adc_agent", this);
        m_sb        = timer_adc_scoreboard::type_id::create("m_sb", this);
        m_cov       = timer_adc_coverage::type_id::create("m_cov", this);

        rm = timer_adc_reg_block::type_id::create("rm");
        rm.build();
        rm.reset();

        m_adapter   = reg2apb_adapter::type_id::create("m_adapter");
        m_predictor = uvm_reg_predictor#(apb_item)::type_id::create("m_predictor", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect RAL model to APB sequencer and explicit monitor predictor
        rm.default_map.set_sequencer(m_apb_agent.sqr, m_adapter);
        rm.default_map.set_auto_predict(0);

        m_predictor.map     = rm.default_map;
        m_predictor.adapter = m_adapter;
        m_apb_agent.ap.connect(m_predictor.bus_in);

        // Connect APB monitor to scoreboard and coverage
        m_apb_agent.ap.connect(m_sb.apb_imp);
        m_apb_agent.ap.connect(m_cov.apb_imp);

        // Connect ADC monitor to scoreboard and coverage
        m_adc_agent.ap.connect(m_sb.adc_imp);
        m_adc_agent.ap.connect(m_cov.adc_imp);
    endfunction

endclass