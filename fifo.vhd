library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- A generic FIFO buffer for storing key presses
entity Data_Queue is
    generic (
        BIT_WIDTH : natural := 8
    );
    port (
        clk, reset  : in std_logic;
        read_req    : in std_logic;
        write_req   : in std_logic;
        write_data  : in std_logic_vector(BIT_WIDTH - 1 downto 0);
        is_empty    : out std_logic;
        is_full     : out std_logic;
        read_data   : out std_logic_vector(BIT_WIDTH - 1 downto 0)
    );
end Data_Queue;

architecture Behavioral of Data_Queue is
    signal buffer_reg : std_logic_vector(BIT_WIDTH - 1 downto 0);
    signal full_flag, empty_flag : std_logic;
    signal full_next, empty_next : std_logic;
    signal control_op : std_logic_vector(1 downto 0);
    signal write_enable : std_logic;
begin

    --========================================================================
    -- Data Storage Process
    -- Stores data when write is enabled
    --========================================================================
    Storage_Proc: process (clk, reset)
    begin
        if reset = '1' then
            buffer_reg <= (others => '0');
        elsif rising_edge(clk) then
            if write_enable = '1' then
                buffer_reg <= write_data;
            end if;
        end if;
    end process;

    read_data <= buffer_reg;
    write_enable <= write_req and (not full_flag);

    --========================================================================
    -- Status Flags Process
    -- Updates the Empty/Full status flags
    --========================================================================
    Flag_Proc: process (clk, reset)
    begin
        if reset = '1' then
            full_flag <= '0';
            empty_flag <= '1';
        elsif rising_edge(clk) then
            full_flag <= full_next;
            empty_flag <= empty_next;
        end if;
    end process;

    -- Logic to determine next state of flags
    control_op <= write_req & read_req;

    Next_Flag_Logic: process (control_op, empty_flag, full_flag)
    begin
        -- Default: keep state
        full_next <= full_flag;
        empty_next <= empty_flag;
        
        case control_op is
            when "00" => -- No Operation
                null;
                
            when "01" => -- Read Operation
                if empty_flag /= '1' then
                    full_next <= '0';
                    empty_next <= '1';
                end if;
                
            when "10" => -- Write Operation
                if full_flag /= '1' then
                    empty_next <= '0';
                    full_next <= '1';
                end if;
                
            when others => -- Simultaneous R/W (not supported in this simple logic, treated as null)
                null;
        end case;
    end process;

    -- Output assignments
    is_full <= full_flag;
    is_empty <= empty_flag;

end Behavioral;
