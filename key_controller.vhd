library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyboard_controller is
    generic (WIDTH_SIZE: integer := 2);
    port (
        sys_clk, reset_in: in std_logic;
        ps2_data, ps2_clock: in std_logic;
        read_enable: in std_logic;
        ascii_key: out std_logic_vector(7 downto 0);
        buffer_empty: out std_logic
    );
end keyboard_controller;

architecture structure of keyboard_controller is
    constant BREAK_CODE: std_logic_vector(7 downto 0):= "11110000"; -- 'F0'
    
    type fsm_states is (WAIT_FOR_BREAK, GET_SCAN_CODE);
    signal current_s, next_s: fsm_states;
    
    signal raw_scan_code, fifo_out_data: std_logic_vector(7 downto 0);
    signal rx_done_pulse, write_to_fifo: std_logic;
    signal final_ascii, processed_key: std_logic_vector(7 downto 0);

begin

   -- Connect the PS/2 Receiver
   u_receiver: entity work.ps2_receiver(rtl)
        port map(
            sys_clk => sys_clk, 
            sys_reset => reset_in, 
            rx_enable => '1',
            ps2_data_line => ps2_data, 
            ps2_clk_line => ps2_clock,
            rx_done_flag => rx_done_pulse,
            data_out => raw_scan_code
        );

   -- Connect the Buffer (FIFO)
   u_buffer: entity work.data_buffer(behavioral)
        generic map(BIT_WIDTH => 8)
        port map(
            clk => sys_clk, 
            rst => reset_in, 
            read_cmd => read_enable,
            write_cmd => write_to_fifo, 
            data_in => raw_scan_code,
            is_empty => buffer_empty, 
            is_full => open,
            data_out => processed_key
        );

   -- Connect the Converter
   u_converter: entity work.scancode_converter(lookup)
        port map (
            scan_input => processed_key,
            ascii_output => final_ascii
        );

   -- State Machine to handle Break Codes (Key Release)
   process (sys_clk, reset_in)
    begin
        if reset_in='1' then
            current_s <= WAIT_FOR_BREAK;
        elsif rising_edge(sys_clk) then
            current_s <= next_s;
        end if;
    end process;

   -- Logic to ignore key press and only register key release (after F0)
   process(current_s, rx_done_pulse, raw_scan_code)
    begin
        write_to_fifo <= '0';
        next_s <= current_s;
        
        case current_s is
            when WAIT_FOR_BREAK => 
                -- Wait for the 'F0' code which indicates key release
                if rx_done_pulse='1' and raw_scan_code = BREAK_CODE then
                    next_s <= GET_SCAN_CODE;
                end if;
                
            when GET_SCAN_CODE => 
                -- Capture the actual key code following 'F0'
                if rx_done_pulse='1' then
                    write_to_fifo <= '1';
                    next_s <= WAIT_FOR_BREAK;
                end if;
        end case;
        
    -- Output the ASCII
    ascii_key <= final_ascii;
    end process;
    
end structure;
