library ieee;
use ieee.std_logic_1164.all;

-- Entity to convert PS/2 make codes to ASCII characters
entity ScanCode_Mapper is
    port (
        scan_in  : in std_logic_vector(7 downto 0);
        ascii_out: out std_logic_vector(7 downto 0)
    );
end ScanCode_Mapper;

architecture Behavioral of ScanCode_Mapper is
begin
    -- Combinational process for Lookup Table
    process(scan_in)
    begin
        case scan_in is
            when "00011100" => ascii_out <= "01000001"; -- A
            when "00110010" => ascii_out <= "01000010"; -- B
            when "00100001" => ascii_out <= "01000011"; -- C
            when "00100011" => ascii_out <= "01000100"; -- D
            when "00100100" => ascii_out <= "01000101"; -- E
            when "00101011" => ascii_out <= "01000110"; -- F
            when "00110100" => ascii_out <= "01000111"; -- G
            when "00110011" => ascii_out <= "01001000"; -- H
            when "01000011" => ascii_out <= "01001001"; -- I
            when "00111011" => ascii_out <= "01001010"; -- J
            when "01000010" => ascii_out <= "01001011"; -- K
            when "01001011" => ascii_out <= "01001100"; -- L
            when "00111010" => ascii_out <= "01001101"; -- M
            when "00110001" => ascii_out <= "01001110"; -- N
            when "01000100" => ascii_out <= "01001111"; -- O
            when "01001101" => ascii_out <= "01010000"; -- P
            when "00010101" => ascii_out <= "01010001"; -- Q
            when "00101101" => ascii_out <= "01010010"; -- R
            when "00011011" => ascii_out <= "01010011"; -- S
            when "00101100" => ascii_out <= "01010100"; -- T
            when "00111100" => ascii_out <= "01010101"; -- U
            when "00101010" => ascii_out <= "01010110"; -- V
            when "00011101" => ascii_out <= "01010111"; -- W
            when "00100010" => ascii_out <= "01011000"; -- X
            when "00110101" => ascii_out <= "01011001"; -- Y
            when "00011010" => ascii_out <= "01011010"; -- Z
            
            -- Numbers
            when "01000101" => ascii_out <= "00110000"; -- 0
            when "00010110" => ascii_out <= "00110001"; -- 1
            when "00011110" => ascii_out <= "00110010"; -- 2
            when "00100110" => ascii_out <= "00110011"; -- 3
            when "00100101" => ascii_out <= "00110100"; -- 4
            when "00101110" => ascii_out <= "00110101"; -- 5
            when "00110110" => ascii_out <= "00110110"; -- 6
            when "00111101" => ascii_out <= "00110111"; -- 7
            when "00111110" => ascii_out <= "00111000"; -- 8
            when "01000110" => ascii_out <= "00111001"; -- 9

            -- Special Characters
            when "00101001" => ascii_out <= "00100000"; -- Space
            when "01011010" => ascii_out <= "00001101"; -- Enter
            when "01100110" => ascii_out <= "00001000"; -- Backspace
            
            when others     => ascii_out <= "00101010"; -- Default (*)
        end case;
    end process;
end Behavioral;
