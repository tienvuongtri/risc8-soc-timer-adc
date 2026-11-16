// =============================================================================
// File: timer_adc_ral.sv
// Description: UVM Register Abstraction Layer (RAL) model for the 16 registers
//              and APB bus adapter
// =============================================================================

// 0x0: TMR_CTRL
class reg_tmr_ctrl extends uvm_reg;
    `uvm_object_utils(reg_tmr_ctrl)
    rand uvm_reg_field en;
    rand uvm_reg_field oneshot;
    uvm_reg_field      rsvd;

    function new(string name = "reg_tmr_ctrl");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        en      = uvm_reg_field::type_id::create("en");
        oneshot = uvm_reg_field::type_id::create("oneshot");
        rsvd    = uvm_reg_field::type_id::create("rsvd");
        en.configure     (this, 1, 0, "RW", 1, 1'b0, 1, 1, 0);
        oneshot.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
        rsvd.configure   (this, 6, 2, "RO", 0, 6'h00, 1, 0, 0);
    endfunction
endclass

// 0x1..0x3, 0x6..0x9: Generic 8-bit RW register
class reg_rw8 extends uvm_reg;
    `uvm_object_utils(reg_rw8)
    rand uvm_reg_field val;

    function new(string name = "reg_rw8");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build_with_reset(uvm_reg_data_t rst_val);
        val = uvm_reg_field::type_id::create("val");
        val.configure(this, 8, 0, "RW", 0, rst_val, 1, 1, 1);
    endfunction
endclass

// 0x4, 0xA, 0xF: Generic 8-bit RO register
class reg_ro8 extends uvm_reg;
    `uvm_object_utils(reg_ro8)
    uvm_reg_field val;

    function new(string name = "reg_ro8");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build_with_reset(uvm_reg_data_t rst_val, bit is_vol);
        val = uvm_reg_field::type_id::create("val");
        val.configure(this, 8, 0, "RO", is_vol, rst_val, 1, 0, 1);
    endfunction
endclass

// 0x5: ADC_CTRL
class reg_adc_ctrl extends uvm_reg;
    `uvm_object_utils(reg_adc_ctrl)
    rand uvm_reg_field en;
    rand uvm_reg_field start;
    rand uvm_reg_field trig_sel;
    rand uvm_reg_field ch;
    uvm_reg_field      rsvd;

    function new(string name = "reg_adc_ctrl");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        en       = uvm_reg_field::type_id::create("en");
        start    = uvm_reg_field::type_id::create("start");
        trig_sel = uvm_reg_field::type_id::create("trig_sel");
        ch       = uvm_reg_field::type_id::create("ch");
        rsvd     = uvm_reg_field::type_id::create("rsvd");
        en.configure      (this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
        // START bit is self-clearing hardware trigger, always reads back 0
        start.configure   (this, 1, 1, "WO", 1, 1'b0, 1, 1, 0);
        trig_sel.configure(this, 2, 2, "RW", 0, 2'b00, 1, 1, 0);
        ch.configure      (this, 2, 4, "RW", 0, 2'b00, 1, 1, 0);
        rsvd.configure    (this, 2, 6, "RO", 0, 2'b00, 1, 0, 0);
    endfunction
endclass

// 0xB: ADC_RCH
class reg_adc_rch extends uvm_reg;
    `uvm_object_utils(reg_adc_rch)
    uvm_reg_field ch;
    uvm_reg_field rsvd;
    uvm_reg_field valid;

    function new(string name = "reg_adc_rch");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        ch    = uvm_reg_field::type_id::create("ch");
        rsvd  = uvm_reg_field::type_id::create("rsvd");
        valid = uvm_reg_field::type_id::create("valid");
        ch.configure   (this, 2, 0, "RO", 1, 2'b00, 1, 0, 0);
        rsvd.configure (this, 5, 2, "RO", 0, 5'h00, 1, 0, 0);
        valid.configure(this, 1, 7, "RO", 1, 1'b0,  1, 0, 0);
    endfunction
endclass

// 0xC: ADC_STAT
class reg_adc_stat extends uvm_reg;
    `uvm_object_utils(reg_adc_stat)
    uvm_reg_field level;
    uvm_reg_field empty;
    uvm_reg_field full;
    uvm_reg_field busy;
    uvm_reg_field rsvd;

    function new(string name = "reg_adc_stat");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        level = uvm_reg_field::type_id::create("level");
        empty = uvm_reg_field::type_id::create("empty");
        full  = uvm_reg_field::type_id::create("full");
        busy  = uvm_reg_field::type_id::create("busy");
        rsvd  = uvm_reg_field::type_id::create("rsvd");
        level.configure(this, 4, 0, "RO", 1, 4'h0, 1, 0, 0);
        empty.configure(this, 1, 4, "RO", 1, 1'b1, 1, 0, 0);
        full.configure (this, 1, 5, "RO", 1, 1'b0, 1, 0, 0);
        busy.configure (this, 1, 6, "RO", 1, 1'b0, 1, 0, 0);
        rsvd.configure (this, 1, 7, "RO", 0, 1'b0, 1, 0, 0);
    endfunction
endclass

// 0xD: IRQ_EN
class reg_irq_en extends uvm_reg;
    `uvm_object_utils(reg_irq_en)
    rand uvm_reg_field en_bits;
    uvm_reg_field      rsvd;

    function new(string name = "reg_irq_en");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        en_bits = uvm_reg_field::type_id::create("en_bits");
        rsvd    = uvm_reg_field::type_id::create("rsvd");
        en_bits.configure(this, 6, 0, "RW", 0, 6'h00, 1, 1, 0);
        rsvd.configure   (this, 2, 6, "RO", 0, 2'b00, 1, 0, 0);
    endfunction
endclass

// 0xE: IRQ_STAT (W1C)
class reg_irq_stat extends uvm_reg;
    `uvm_object_utils(reg_irq_stat)
    rand uvm_reg_field stat_bits;
    uvm_reg_field      rsvd;

    function new(string name = "reg_irq_stat");
        super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        stat_bits = uvm_reg_field::type_id::create("stat_bits");
        rsvd      = uvm_reg_field::type_id::create("rsvd");
        stat_bits.configure(this, 6, 0, "W1C", 1, 6'h00, 1, 1, 0);
        rsvd.configure     (this, 2, 6, "RO",  0, 2'b00, 1, 0, 0);
    endfunction
endclass

// -----------------------------------------------------------------------------
// Register Block (16 bytes: 0x0 .. 0xF)
// -----------------------------------------------------------------------------
class timer_adc_reg_block extends uvm_reg_block;

    `uvm_object_utils(timer_adc_reg_block)

    rand reg_tmr_ctrl tmr_ctrl;
    rand reg_rw8      tmr_presc;
    rand reg_rw8      tmr_load;
    rand reg_rw8      tmr_cmp;
    reg_ro8           tmr_cnt;
    rand reg_adc_ctrl adc_ctrl;
    rand reg_rw8      adc_smp;
    rand reg_rw8      adc_div;
    rand reg_rw8      adc_thr_lo;
    rand reg_rw8      adc_thr_hi;
    reg_ro8           adc_data;
    reg_adc_rch       adc_rch;
    reg_adc_stat      adc_stat;
    rand reg_irq_en   irq_en;
    rand reg_irq_stat irq_stat;
    reg_ro8           id;

    uvm_reg_map default_map;

    function new(string name = "timer_adc_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        tmr_ctrl = reg_tmr_ctrl::type_id::create("tmr_ctrl");
        tmr_ctrl.configure(this);
        tmr_ctrl.build();

        tmr_presc = reg_rw8::type_id::create("tmr_presc");
        tmr_presc.configure(this);
        tmr_presc.build_with_reset(8'h00);

        tmr_load = reg_rw8::type_id::create("tmr_load");
        tmr_load.configure(this);
        tmr_load.build_with_reset(8'hFF);

        tmr_cmp = reg_rw8::type_id::create("tmr_cmp");
        tmr_cmp.configure(this);
        tmr_cmp.build_with_reset(8'h80);

        tmr_cnt = reg_ro8::type_id::create("tmr_cnt");
        tmr_cnt.configure(this);
        tmr_cnt.build_with_reset(8'h00, 1'b1);

        adc_ctrl = reg_adc_ctrl::type_id::create("adc_ctrl");
        adc_ctrl.configure(this);
        adc_ctrl.build();

        adc_smp = reg_rw8::type_id::create("adc_smp");
        adc_smp.configure(this);
        adc_smp.build_with_reset(8'h04);

        adc_div = reg_rw8::type_id::create("adc_div");
        adc_div.configure(this);
        adc_div.build_with_reset(8'h00);

        adc_thr_lo = reg_rw8::type_id::create("adc_thr_lo");
        adc_thr_lo.configure(this);
        adc_thr_lo.build_with_reset(8'h00);

        adc_thr_hi = reg_rw8::type_id::create("adc_thr_hi");
        adc_thr_hi.configure(this);
        adc_thr_hi.build_with_reset(8'hFF);

        adc_data = reg_ro8::type_id::create("adc_data");
        adc_data.configure(this);
        adc_data.build_with_reset(8'h00, 1'b1);

        adc_rch = reg_adc_rch::type_id::create("adc_rch");
        adc_rch.configure(this);
        adc_rch.build();

        adc_stat = reg_adc_stat::type_id::create("adc_stat");
        adc_stat.configure(this);
        adc_stat.build();

        irq_en = reg_irq_en::type_id::create("irq_en");
        irq_en.configure(this);
        irq_en.build();

        irq_stat = reg_irq_stat::type_id::create("irq_stat");
        irq_stat.configure(this);
        irq_stat.build();

        id = reg_ro8::type_id::create("id");
        id.configure(this);
        id.build_with_reset(8'hA8, 1'b0);

        default_map = create_map("default_map", 'h0, 1, UVM_LITTLE_ENDIAN);
        default_map.add_reg(tmr_ctrl,   'h0, "RW");
        default_map.add_reg(tmr_presc,  'h1, "RW");
        default_map.add_reg(tmr_load,   'h2, "RW");
        default_map.add_reg(tmr_cmp,    'h3, "RW");
        default_map.add_reg(tmr_cnt,    'h4, "RO");
        default_map.add_reg(adc_ctrl,   'h5, "RW");
        default_map.add_reg(adc_smp,    'h6, "RW");
        default_map.add_reg(adc_div,    'h7, "RW");
        default_map.add_reg(adc_thr_lo, 'h8, "RW");
        default_map.add_reg(adc_thr_hi, 'h9, "RW");
        default_map.add_reg(adc_data,   'hA, "RO");
        default_map.add_reg(adc_rch,    'hB, "RO");
        default_map.add_reg(adc_stat,   'hC, "RO");
        default_map.add_reg(irq_en,     'hD, "RW");
        default_map.add_reg(irq_stat,   'hE, "RW");
        default_map.add_reg(id,         'hF, "RO");

        lock_model();
    endfunction

endclass

// -----------------------------------------------------------------------------
// RAL-to-APB Adapter
// -----------------------------------------------------------------------------
class reg2apb_adapter extends uvm_reg_adapter;

    `uvm_object_utils(reg2apb_adapter)

    function new(string name = "reg2apb_adapter");
        super.new(name);
        supports_byte_enable = 0;
        provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        apb_item item = apb_item::type_id::create("item");
        item.pwrite = (rw.kind == UVM_WRITE) ? 1'b1 : 1'b0;
        item.paddr  = rw.addr[3:0];
        item.pwdata = rw.data[7:0];
        return item;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        apb_item item;
        if (!$cast(item, bus_item)) begin
            `uvm_fatal("RAL_ADAPTER", "Provided bus_item is not of type apb_item")
        end
        rw.kind   = item.pwrite ? UVM_WRITE : UVM_READ;
        rw.addr   = {4'h0, item.paddr};
        rw.data   = item.pwrite ? item.pwdata : item.prdata;
        rw.status = item.pslverr ? UVM_NOT_OK : UVM_IS_OK;
    endfunction

endclass