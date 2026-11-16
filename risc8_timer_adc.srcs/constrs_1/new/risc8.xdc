## Clock constraint: 100 MHz (10.000 ns period)
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

## Input / Output delay constraints for timing analysis
set_input_delay  -clock [get_clocks sys_clk_pin] -min 1.000 [get_ports {rst}]
set_input_delay  -clock [get_clocks sys_clk_pin] -max 2.000 [get_ports {rst}]