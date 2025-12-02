library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hangman_game is
    Port (
        LCD_DATA_BUS : out std_logic_vector(7 downto 0); -- LCD DB pins
        LCD_RS : out std_logic; -- Register Select
        LCD_RW : out std_logic; -- Read/Write
        LCD_E : out std_logic;  -- Enable
        SYS_CLK : in std_logic; -- 50MHz Clock
        RESET_BTN : in std_logic; -- Reset Button
        
        -- PS/2 connections
        PS2_DATA_PIN, PS2_CLK_PIN : in std_logic; 
        
        -- LEDs for debug
        LED_OUTPUT : out std_logic_vector(7 downto 0) 
    );
end hangman_game;

architecture behavioral of hangman_game is

    -- Component Instantiation
    component keyboard_controller is
        port (
            sys_clk, reset_in : in std_logic;
            ps2_data, ps2_clock : in std_logic;
            read_enable : in std_logic;
            ascii_key : out std_logic_vector(7 downto 0);
            buffer_empty : out std_logic
        );
    end component keyboard_controller;

    -- State Machines
    type main_fsm is (
        s_PowerDelay, s_FuncSet, s_FuncSet_Wait,
        s_DispCtrl, s_DispCtrl_Wait, s_ClearDisp,
        s_ClearDisp_Wait, s_InitDone, s_WriteAct, s_CharWait, s_Idle
    );
    
    type write_fsm is (w_Idle, w_SetRW, w_EnablePulse);
    type game_fsm is (STATE_WAIT_INPUT, STATE_PROCESS_INPUT);

    -- Timing Signals
    signal clk_divider : integer range 0 to 49 := 0;
    signal tick_1mhz : std_logic := '0';
    signal delay_timer : unsigned(16 downto 0) := (others => '0');
    signal timer_done : std_logic := '0';
    
    -- State Signals
    signal current_s : main_fsm := s_PowerDelay;
    signal next_s : main_fsm;
    signal write_s : write_fsm := w_Idle;
    signal next_write_s : write_fsm;
    signal trigger_write : std_logic := '0';
    
    -- Keyboard Signals
    signal read_req : std_logic;
    signal received_char : std_logic_vector(7 downto 0);
    signal last_char : std_logic_vector(7 downto 0) := (others => '0');
    signal is_kb_empty : std_logic;
    
    -- Game Logic Variables
    signal lives_left : unsigned(3 downto 0) := "0110"; -- Starts with 6 lives
    signal is_game_over : std_logic;

    -- Display Memory
    type COMMAND_ARRAY is array (integer range 0 to 27) of std_logic_vector(9 downto 0);
    signal bit_mask : std_logic_vector(6 downto 0) := (others => '0'); -- Correct guesses mask
    signal lcd_instructions : COMMAND_ARRAY;
    signal instr_ptr : integer range 0 to COMMAND_ARRAY'HIGH + 1 := 0;
    
    signal input_state : game_fsm := STATE_WAIT_INPUT;

    -- === WORD BANK (ROM) ===
    -- Supporting up to 7 characters. Shorter words are padded with spaces (0x20).
    type word_t is array (0 to 6) of std_logic_vector(7 downto 0);
    type rom_t is array (0 to 4) of word_t;
    
    constant WORD_ROM : rom_t := (
        (X"54", X"45", X"54", X"52", X"41", X"20", X"20"), -- TETRA
        (X"43", X"4F", X"50", X"41", X"20", X"20", X"20"), -- COPA
        (X"4C", X"49", X"56", X"52", X"45", X"54", X"41"), -- LIBERTA 
        (X"44", X"4F", X"52", X"45", X"53", X"20", X"20"), -- DORES
        (X"4D", X"45", X"4E", X"47", X"4F", X"20", X"20")  -- MENGO
    );
    -- Note: LIBERTA hex: L(4C) I(49) B(42) E(45) R(52) T(54) A(41)
    
    signal current_word_idx : integer range 0 to 4 := 0;

begin

    -- Instantiate Keyboard
    u_kb: keyboard_controller PORT MAP(
        sys_clk => SYS_CLK, 
        reset_in => RESET_BTN, 
        ps2_data => PS2_DATA_PIN, 
        ps2_clock => PS2_CLK_PIN, 
        read_enable => read_req, 
        ascii_key => received_char, 
        buffer_empty => is_kb_empty
    );

    -- 1MHz Tick Generator for LCD Timing
    process (SYS_CLK, RESET_BTN)
    begin
        if RESET_BTN = '1' then
            clk_divider <= 0;
            tick_1mhz <= '0';
        elsif rising_edge(SYS_CLK) then
            tick_1mhz <= '0';
            if clk_divider = 49 then
                clk_divider <= 0;
                tick_1mhz <= '1';
            else
                clk_divider <= clk_divider + 1;
            end if;
        end if;
    end process;

    -- =========================================================
    -- MAIN GAME LOGIC
    -- =========================================================
    process (SYS_CLK, RESET_BTN)
        variable char_match : boolean;
        variable next_word : integer;
    begin
        if RESET_BTN = '1' then
            read_req <= '0';
            last_char <= (others => '0');
            lives_left <= "0110"; 
            
            -- Initialize mask: Set bits to '1' for spaces, '0' for letters
            for k in 0 to 6 loop
                if WORD_ROM(0)(k) = X"20" then
                    bit_mask(6-k) <= '1';
                else
                    bit_mask(6-k) <= '0';
                end if;
            end loop;
            
            input_state <= STATE_WAIT_INPUT;
            current_word_idx <= 0; 
            
        elsif rising_edge(SYS_CLK) then
            
            case input_state is
                when STATE_WAIT_INPUT =>
                    read_req <= '0';
                    -- Check if keyboard has data
                    if is_kb_empty = '0' then
                        read_req <= '1'; -- Pop from FIFO
                        last_char <= received_char; 
                        LED_OUTPUT <= received_char; -- Show on LEDs
                        
                        -- === RESTART LOGIC (ENTER KEY) ===
                        if is_game_over = '1' then
                            if received_char = X"0D" then -- 0x0D is Enter
                                lives_left <= "0110";   
                                
                                -- Cycle to next word
                                if current_word_idx = 4 then 
                                    next_word := 0; 
                                else 
                                    next_word := current_word_idx + 1; 
                                end if;
                                current_word_idx <= next_word;

                                -- Auto-solve spaces for the new word
                                for k in 0 to 6 loop
                                    if WORD_ROM(next_word)(k) = X"20" then
                                        bit_mask(6-k) <= '1';
                                    else
                                        bit_mask(6-k) <= '0';
                                    end if;
                                end loop;
                            end if;

                        -- === NORMAL GAMEPLAY ===
                        else
                            -- Check if input is Uppercase A-Z (0x41 to 0x5A)
                            if (received_char >= X"41" and received_char <= X"5A") then
                                char_match := false;
                                -- Loop through current word
                                for k in 0 to 6 loop
                                    if received_char = WORD_ROM(current_word_idx)(k) then
                                        bit_mask(6-k) <= '1'; -- Reveal letter (Mapping logic: 6=Left, 0=Right)
                                        char_match := true;
                                    end if;
                                end loop;

                                -- If wrong guess, decrease life
                                if char_match = false then
                                    if lives_left > 0 then
                                        lives_left <= lives_left - 1;
                                    end if;
                                end if;
                            end if;
                        end if;
                        input_state <= STATE_PROCESS_INPUT;
                    end if;

                when STATE_PROCESS_INPUT =>
                    read_req <= '0';
                    input_state <= STATE_WAIT_INPUT;
            end case;
        end if;
    end process;

    -- Game Over Flag: Win (all 1s) or Lose (0 lives)
    is_game_over <= '1' when (lives_left = 0 or bit_mask = "1111111") else '0';

    -- =========================================================
    -- LCD CONTENT UPDATE
    -- =========================================================
    process (is_game_over, lives_left, bit_mask, current_word_idx)
    begin
        -- Init Commands
        lcd_instructions(0) <= "00" & X"38"; -- 8-bit mode
        lcd_instructions(1) <= "00" & X"0C"; -- Display ON, Cursor OFF
        lcd_instructions(2) <= "00" & X"01"; -- Clear
        lcd_instructions(3) <= "00" & X"06"; -- Entry mode
        lcd_instructions(17) <= "00" & X"C0"; -- Move to Line 2, Pos 0

        -- Move cursor for Life Counter (Line 2, Pos 13)
        lcd_instructions(25) <= "00" & X"CD"; 
        
        -- Reset cursor to start (Line 1, Pos 0)
        lcd_instructions(27) <= "00" & X"80";

        -- DEFAULT MESSAGE: "JOGO DA FORCA"
        lcd_instructions(4)  <= "10" & X"4A"; -- J
        lcd_instructions(5)  <= "10" & X"4F"; -- O
        lcd_instructions(6)  <= "10" & X"47"; -- G
        lcd_instructions(7)  <= "10" & X"4F"; -- O
        lcd_instructions(8)  <= "10" & X"20"; -- Space
        lcd_instructions(9)  <= "10" & X"44"; -- D
        lcd_instructions(10) <= "10" & X"41"; -- A
        lcd_instructions(11) <= "10" & X"20"; -- Space
        lcd_instructions(12) <= "10" & X"46"; -- F
        lcd_instructions(13) <= "10" & X"4F"; -- O
        lcd_instructions(14) <= "10" & X"52"; -- R
        lcd_instructions(15) <= "10" & X"43"; -- C
        lcd_instructions(16) <= "10" & X"41"; -- A

        -- END GAME MESSAGES (Overwrites Line 1)
        if is_game_over = '1' then
            if bit_mask = "1111111" then -- WINNER
                lcd_instructions(4)  <= "10" & X"56"; -- V
                lcd_instructions(5)  <= "10" & X"4F"; -- O
                lcd_instructions(6)  <= "10" & X"43"; -- C
                lcd_instructions(7)  <= "10" & X"45"; -- E
                lcd_instructions(8)  <= "10" & X"20";
                lcd_instructions(9)  <= "10" & X"47"; -- G
                lcd_instructions(10) <= "10" & X"41"; -- A
                lcd_instructions(11) <= "10" & X"4E"; -- N
                lcd_instructions(12) <= "10" & X"48"; -- H
                lcd_instructions(13) <= "10" & X"4F"; -- O
                lcd_instructions(14) <= "10" & X"55"; -- U
                lcd_instructions(15) <= "10" & X"20";
                lcd_instructions(16) <= "10" & X"20";
            elsif lives_left = 0 then -- LOSER
                lcd_instructions(4)  <= "10" & X"56"; -- V
                lcd_instructions(5)  <= "10" & X"4F"; -- O
                lcd_instructions(6)  <= "10" & X"43"; -- C
                lcd_instructions(7)  <= "10" & X"45"; -- E
                lcd_instructions(8)  <= "10" & X"20";
                lcd_instructions(9)  <= "10" & X"50"; -- P
                lcd_instructions(10) <= "10" & X"45"; -- E
                lcd_instructions(11) <= "10" & X"52"; -- R
                lcd_instructions(12) <= "10" & X"44"; -- D
                lcd_instructions(13) <= "10" & X"45"; -- E
                lcd_instructions(14) <= "10" & X"55"; -- U
                lcd_instructions(15) <= "10" & X"20";
                lcd_instructions(16) <= "10" & X"20";
            end if;
        end if;

        -- === DYNAMIC WORD DISPLAY (Line 2) ===
        -- If bit is 1, show letter. If 0, show underline.
        -- Note: WORD_ROM spaces (0x20) are effectively invisible when shown.
        
        if (bit_mask(6) = '1') then lcd_instructions(18) <= "10" & WORD_ROM(current_word_idx)(0); else lcd_instructions(18) <= "10" & X"5F"; end if;
        if (bit_mask(5) = '1') then lcd_instructions(19) <= "10" & WORD_ROM(current_word_idx)(1); else lcd_instructions(19) <= "10" & X"5F"; end if;
        if (bit_mask(4) = '1') then lcd_instructions(20) <= "10" & WORD_ROM(current_word_idx)(2); else lcd_instructions(20) <= "10" & X"5F"; end if;
        if (bit_mask(3) = '1') then lcd_instructions(21) <= "10" & WORD_ROM(current_word_idx)(3); else lcd_instructions(21) <= "10" & X"5F"; end if;
        if (bit_mask(2) = '1') then lcd_instructions(22) <= "10" & WORD_ROM(current_word_idx)(4); else lcd_instructions(22) <= "10" & X"5F"; end if;
        if (bit_mask(1) = '1') then lcd_instructions(23) <= "10" & WORD_ROM(current_word_idx)(5); else lcd_instructions(23) <= "10" & X"5F"; end if;
        if (bit_mask(0) = '1') then lcd_instructions(24) <= "10" & WORD_ROM(current_word_idx)(6); else lcd_instructions(24) <= "10" & X"5F"; end if;

        -- Life Counter (Command 26)
        case (lives_left) is
            when "0110" => lcd_instructions(26) <= "10" & X"36"; -- 6
            when "0101" => lcd_instructions(26) <= "10" & X"35"; -- 5
            when "0100" => lcd_instructions(26) <= "10" & X"34"; -- 4
            when "0011" => lcd_instructions(26) <= "10" & X"33"; -- 3
            when "0010" => lcd_instructions(26) <= "10" & X"32"; -- 2
            when "0001" => lcd_instructions(26) <= "10" & X"31"; -- 1
            when others => lcd_instructions(26) <= "10" & X"30"; -- 0
        end case;
    end process;

    -- Delay Counter Implementation
    process (SYS_CLK, RESET_BTN)
    begin
        if RESET_BTN = '1' then
            delay_timer <= (others => '0');
        elsif rising_edge(SYS_CLK) then
            if tick_1mhz = '1' then
                if timer_done = '1' then
                    delay_timer <= (others => '0');
                else
                    delay_timer <= delay_timer + 1;
                end if;
            end if;
        end if;
    end process;

    -- Timer Logic for LCD initialization steps
    timer_done <= '1' when ((current_s = s_PowerDelay and delay_timer >= 40000) or 
                            (current_s = s_FuncSet_Wait and delay_timer >= 100) or   
                            (current_s = s_DispCtrl_Wait and delay_timer >= 100) or  
                            (current_s = s_ClearDisp_Wait and delay_timer >= 3200) or  
                            (current_s = s_CharWait and delay_timer >= 80))         
               else '0';

    -- LCD Controller FSM
    process (SYS_CLK, RESET_BTN)
    begin
        if RESET_BTN = '1' then
            current_s <= s_PowerDelay;
            instr_ptr <= 0;
        elsif rising_edge(SYS_CLK) then
             if tick_1mhz = '1' then 
                 current_s <= next_s;
                 if timer_done = '1' then 
                     case current_s is
                         when s_PowerDelay => instr_ptr <= 0;
                         when s_FuncSet_Wait => instr_ptr <= 1;
                         when s_DispCtrl_Wait => instr_ptr <= 2;
                         when s_ClearDisp_Wait => instr_ptr <= 3;
                         when s_CharWait => 
                             -- Loop logic for screen refresh
                             if instr_ptr = 3 then 
                                 instr_ptr <= 4;
                             elsif instr_ptr = COMMAND_ARRAY'HIGH then 
                                 instr_ptr <= 4;
                             else
                                 instr_ptr <= instr_ptr + 1;
                             end if;
                         when others => null;
                     end case;
                 end if;
            end if;
        end if;
    end process;

    -- Next State Logic
    process (current_s, timer_done, instr_ptr, lcd_instructions) 
    begin
        LCD_RS <= lcd_instructions(instr_ptr)(9);
        LCD_RW <= lcd_instructions(instr_ptr)(8);
        LCD_DATA_BUS <= lcd_instructions(instr_ptr)(7 downto 0);
        trigger_write <= '0';
        next_s <= current_s;
        
        case current_s is
            when s_PowerDelay => if timer_done = '1' then next_s <= s_FuncSet; end if;
            when s_FuncSet => trigger_write <= '1'; next_s <= s_FuncSet_Wait;
            when s_FuncSet_Wait => if timer_done = '1' then next_s <= s_DispCtrl; end if;
            when s_DispCtrl => trigger_write <= '1'; next_s <= s_DispCtrl_Wait;
            when s_DispCtrl_Wait => if timer_done = '1' then next_s <= s_ClearDisp; end if;
            when s_ClearDisp => trigger_write <= '1'; next_s <= s_ClearDisp_Wait;
            when s_ClearDisp_Wait => if timer_done = '1' then next_s <= s_InitDone; end if;
            when s_InitDone => next_s <= s_WriteAct;
            when s_WriteAct => trigger_write <= '1'; next_s <= s_CharWait;
            when s_CharWait => if timer_done = '1' then next_s <= s_InitDone; end if;
            when s_Idle => next_s <= s_Idle;
        end case;
    end process;
    
    -- Write Signal FSM
    process (SYS_CLK, RESET_BTN)
    begin
        if RESET_BTN = '1' then
            write_s <= w_Idle;
        elsif rising_edge(SYS_CLK) then
             if tick_1mhz = '1' then 
                write_s <= next_write_s;
             end if;
        end if;
    end process;

     process (write_s, trigger_write)
     begin
         next_write_s <= write_s;
         case write_s is
             when w_Idle => if trigger_write = '1' then next_write_s <= w_SetRW; end if;
             when w_SetRW => next_write_s <= w_EnablePulse;
             when w_EnablePulse => next_write_s <= w_Idle;
         end case;
     end process;

     LCD_E <= '1' when write_s = w_EnablePulse else '0';
     
end behavioral;
