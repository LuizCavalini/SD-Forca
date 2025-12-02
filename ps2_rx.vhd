library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_receiver is
    port (
        sys_clk, sys_reset : in std_logic;
        ps2_data_line, ps2_clk_line : in std_logic;
        rx_enable : in std_logic;
        rx_done_flag : out std_logic;
        data_out : out std_logic_vector(7 downto 0)
    );
end ps2_receiver;

architecture rtl of ps2_receiver is
    type machine_state is (STATE_IDLE, STATE_RECEIVE, STATE_LOAD);
    signal curr_state, next_state : machine_state;
    
    signal filter_reg, filter_next : std_logic_vector(7 downto 0);
    signal f_ps2c_reg, f_ps2c_next : std_logic;
    
    signal shift_reg, shift_next : std_logic_vector(10 downto 0);
    signal count_reg, count_next : unsigned(3 downto 0);
    signal falling_edge_tick : std_logic;
begin

    -- Filter inputs to remove noise from the PS/2 clock line
    process (sys_clk, sys_reset)
    begin
        if sys_reset = '1' then
            filter_reg <= (others => '0');
            f_ps2c_reg <= '0';
        elsif rising_edge(sys_clk) then
            filter_reg <= filter_next;
            f_ps2c_reg <= f_ps2c_next;
        end if;
    end process;

    filter_next <= ps2_clk_line & filter_reg(7 downto 1);
    
    -- Detect stable logic level
    f_ps2c_next <= '1' when filter_reg = "11111111" else
                   '0' when filter_reg = "00000000" else
                   f_ps2c_reg;
                   
    -- Detect falling edge
    falling_edge_tick <= f_ps2c_reg and (not f_ps2c_next);

    -- FSMD (Finite State Machine with Datapath) for data extraction
    process (sys_clk, sys_reset)
    begin
        if sys_reset = '1' then
            curr_state <= STATE_IDLE;
            count_reg <= (others => '0');
            shift_reg <= (others => '0');
        elsif rising_edge(sys_clk) then
            curr_state <= next_state;
            count_reg <= count_next;
            shift_reg <= shift_next;
        end if;
    end process;

    -- Next state logic
    process (curr_state, count_reg, shift_reg, falling_edge_tick, rx_enable, ps2_data_line)
    begin
        rx_done_flag <= '0';
        next_state <= curr_state;
        count_next <= count_reg;
        shift_next <= shift_reg;

        case curr_state is
            when STATE_IDLE =>
                if falling_edge_tick = '1' and rx_enable = '1' then
                    -- Start bit detected, shift in data
                    shift_next <= ps2_data_line & shift_reg(10 downto 1);
                    count_next <= "1001"; -- Counter set for 8 data + 1 parity + 1 stop
                    next_state <= STATE_RECEIVE;
                end if;

            when STATE_RECEIVE =>
                if falling_edge_tick = '1' then
                    shift_next <= ps2_data_line & shift_reg(10 downto 1);
                    if count_reg = 0 then
                        next_state <= STATE_LOAD;
                    else
                        count_next <= count_reg - 1;
                    end if;
                end if;

            when STATE_LOAD =>
                -- Signal completion
                next_state <= STATE_IDLE;
                rx_done_flag <= '1';
        end case;
    end process;

    -- Output the 8-bit data frame
    data_out <= shift_reg(8 downto 1);

end rtl;
