library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-level Keyboard Controller
-- Coordinates the Receiver, Buffer, and ASCII Converter
entity Keyboard_Controller is
    port (
        clk, reset      : in std_logic;
        ps2d, ps2c      : in std_logic;
        rd_command      : in std_logic;
        ascii_key       : out std_logic_vector(7 downto 0);
        buffer_empty    : out std_logic
    );
end Keyboard_Controller;

architecture Behavioral of Keyboard_Controller is
    -- Break Code constant (Key release)
    constant BREAK_CODE : std_logic_vector(7 downto 0):= "11110000";
    
    type fsm_state is (Wait_Break_Code, Retrieve_Code);
    signal current_st, next_st : fsm_state;
    
    signal raw_scan_code : std_logic_vector(7 downto 0);
    signal scan_ready : std_logic;
    signal code_captured : std_logic;
    
    signal buffered_scan_code : std_logic_vector(7 downto 0);
    signal converted_ascii : std_logic_vector(7 downto 0);

begin

    -- 1. Instantiate PS/2 Receiver
    RX_Unit: entity work.PS2_Interface(Behavioral)
        port map(
            clk => clk, 
            reset => reset, 
            rx_en => '1',
            ps2d => ps2d, 
            ps2c => ps2c,
            rx_done_tick => scan_ready,
            dout => raw_scan_code
        );

    -- 2. Instantiate FIFO Buffer
    Buffer_Unit: entity work.Data_Queue(Behavioral)
        generic map(BIT_WIDTH => 8)
        port map(
            clk => clk, 
            reset => reset, 
            rd => rd_command,
            wr => code_captured, 
            w_data => raw_scan_code,
            empty => buffer_empty, 
            full => open,
            r_data => buffered_scan_code
        );

    -- 3. Instantiate ASCII Mapper
    Converter_Unit: entity work.ScanCode_Mapper(Behavioral)
        port map (
            scan_in => buffered_scan_code,
            ascii_out => converted_ascii
        );

    --========================================================================
    -- FSM: Scan Code Processing
    -- logic to filter out the 'Break' code (F0) processing
    --========================================================================
    process (clk, reset)
    begin
        if reset = '1' then
            current_st <= Wait_Break_Code;
        elsif rising_edge(clk) then
            current_st <= next_st;
        end if;
    end process;

    process(current_st, scan_ready, raw_scan_code)
    begin
        code_captured <= '0';
        next_st <= current_st;
        
        case current_st is
            -- Wait for the key release indicator (F0)
            when Wait_Break_Code => 
                if scan_ready = '1' and raw_scan_code = BREAK_CODE then
                    next_st <= Retrieve_Code;
                end if;
            
            -- Capture the actual key code that follows F0
            when Retrieve_Code => 
                if scan_ready = '1' then
                    code_captured <= '1';
                    next_st <= Wait_Break_Code;
                end if;
        end case;
    end process;
    
    ascii_key <= converted_ascii;

end Behavioral;
