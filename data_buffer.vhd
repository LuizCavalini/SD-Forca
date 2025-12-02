library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_buffer is
    generic (
        BIT_WIDTH : natural := 8 
    );
    port (
        clk, rst : in std_logic;
        read_cmd, write_cmd : in std_logic;
        data_in : in std_logic_vector(BIT_WIDTH - 1 downto 0);
        is_empty, is_full : out std_logic;
        data_out : out std_logic_vector(BIT_WIDTH - 1 downto 0)
    );
end data_buffer;

architecture behavioral of data_buffer is
    signal stored_data : std_logic_vector(BIT_WIDTH - 1 downto 0);
    signal full_flag, empty_flag : std_logic;
    signal full_next, empty_next : std_logic;
    signal operation_code : std_logic_vector(1 downto 0);
    signal write_enable : std_logic;
begin
    -- Memory register process
    process (clk, rst)
    begin
        if (rst = '1') then
            stored_data <= (others => '0');
        elsif rising_edge(clk) then
            if write_enable = '1' then
                stored_data <= data_in;
            end if;
        end if;
    end process;

    -- Output assignment
    data_out <= stored_data;
    
    -- Safety: Allow write only if not full
    write_enable <= write_cmd and (not full_flag);

    -- Pointer control logic
    process (clk, rst)
    begin
        if (rst = '1') then
            full_flag <= '0';
            empty_flag <= '1';
        elsif rising_edge(clk) then
            full_flag <= full_next;
            empty_flag <= empty_next;
        end if;
    end process;

    -- Logic for next state of flags
    operation_code <= write_cmd & read_cmd;
    
    process (operation_code, empty_flag, full_flag)
    begin
        full_next <= full_flag;
        empty_next <= empty_flag;
        
        case operation_code is
            when "00" => -- Idle
                null;
            when "01" => -- Read operation
                if (empty_flag /= '1') then 
                    full_next <= '0';
                    empty_next <= '1';
                end if;
            when "10" => -- Write operation
                if (full_flag /= '1') then 
                    empty_next <= '0';
                    full_next <= '1';
                end if;
            when others => -- Simultaneous R/W
                null;
        end case;
    end process;

    is_full <= full_flag;
    is_empty <= empty_flag;
end behavioral;
