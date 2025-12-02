library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Entity for receiving raw data from PS/2 Keyboard
entity PS2_Interface is
    port (
        clk, reset  : in std_logic;
        ps2d, ps2c  : in std_logic; -- Data and Clock lines from keyboard
        rx_en       : in std_logic; -- Receiver enable signal
        rx_done_tick: out std_logic; -- Flag indicating new data ready
        dout        : out std_logic_vector(7 downto 0) -- Output data byte
    );
end PS2_Interface;

architecture Behavioral of PS2_Interface is
    -- State Machine definitions
    type state_type is (Idle, RxData, RxStopBit);
    signal current_state, next_state : state_type;
    
    -- Internal registers for filtering and shifting
    signal filter_reg, filter_next : std_logic_vector(7 downto 0);
    signal ps2c_filtered, ps2c_filtered_next : std_logic;
    signal shift_reg, shift_next : std_logic_vector(10 downto 0); -- Stores the full frame
    signal bit_cnt, bit_cnt_next : unsigned(3 downto 0); -- Counter for bits received
    signal falling_edge : std_logic;

begin

    --========================================================================
    -- Process: Input Filtering
    -- Filters noise on the PS/2 clock line to detect a stable falling edge
    --========================================================================
    Filter_Logic: process (clk, reset)
    begin
        if reset = '1' then
            filter_reg <= (others => '0');
            ps2c_filtered <= '0';
        elsif rising_edge(clk) then
            filter_reg <= filter_next;
            ps2c_filtered <= ps2c_filtered_next;
        end if;
    end process;

    filter_next <= ps2c & filter_reg(7 downto 1);
    
    -- Determine filtered state based on history
    ps2c_filtered_next <= '1' when filter_reg = "11111111" else
                          '0' when filter_reg = "00000000" else
                          ps2c_filtered;
                          
    -- Detect falling edge
    falling_edge <= ps2c_filtered and (not ps2c_filtered_next);

    --========================================================================
    -- Process: FSM Registers
    -- Updates the state and data registers on system clock
    --========================================================================
    FSM_Regs: process (clk, reset)
    begin
        if reset = '1' then
            current_state <= Idle;
            bit_cnt <= (others => '0');
            shift_reg <= (others => '0');
        elsif rising_edge(clk) then
            current_state <= next_state;
            bit_cnt <= bit_cnt_next;
            shift_reg <= shift_next;
        end if;
    end process;

    --========================================================================
    -- Process: Next State Logic
    -- Controls the flow of data reception (Start -> Data -> Stop)
    --========================================================================
    Next_State_Logic: process (current_state, bit_cnt, shift_reg, falling_edge, rx_en, ps2d)
    begin
        -- Defaults
        rx_done_tick <= '0';
        next_state <= current_state;
        bit_cnt_next <= bit_cnt;
        shift_reg_next <= shift_reg; -- (Correction: logic uses signals below directly)
        
        -- Override shift register logic manually in case statement to match original logic
        -- (Defined shift_next and bit_cnt_next logic below)
        
        case current_state is
            when Idle =>
                if falling_edge = '1' and rx_en = '1' then
                    -- Start bit detected, load initial values
                    -- Shift in the start bit (ps2d) into MSB
                    shift_next <= ps2d & shift_reg(10 downto 1);
                    bit_cnt_next <= "1001"; -- Set counter for 9 remaining bits
                    next_state <= RxData;
                else
                    shift_next <= shift_reg;
                end if;

            when RxData =>
                if falling_edge = '1' then
                    shift_next <= ps2d & shift_reg(10 downto 1);
                    if bit_cnt = 0 then
                        next_state <= RxStopBit;
                    else
                        bit_cnt_next <= bit_cnt - 1;
                    end if;
                else
                     shift_next <= shift_reg;
                end if;

            when RxStopBit =>
                -- Allow time for the stop bit logic to settle
                next_state <= Idle;
                rx_done_tick <= '1'; -- Signal completion
                shift_next <= shift_reg;
        end case;
    end process;

    -- Output the data byte (discard start/stop/parity)
    dout <= shift_reg(8 downto 1);

end Behavioral;
