library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Top Level Entity for the Hangman Game System
entity Hangman_System is
    Port (
        LCD_DB : out std_logic_vector(7 downto 0); -- LCD Data Bus
        RS     : out std_logic;                    -- Register Select
        RW     : out std_logic;                    -- Read/Write
        E      : out std_logic;                    -- Enable
        CLK    : in std_logic;                     -- System Clock
        rst    : in std_logic;                     -- Reset
        ps2d, ps2c : in std_logic;                 -- Keyboard Input
        tecla  : out std_logic_vector(7 downto 0)  -- Debug LEDs
    );
end Hangman_System;

architecture Behavioral of Hangman_System is

    -- Keyboard Controller Component Definition
    component Keyboard_Controller is
        port (
            clk, reset    : in std_logic;
            ps2d, ps2c    : in std_logic;
            rd_command    : in std_logic;
            ascii_key     : out std_logic_vector(7 downto 0);
            buffer_empty  : out std_logic
        );
    end component Keyboard_Controller;

    -- State Machines Definitions
    type main_fsm_type is (
        PowerOnWait, SetFunc, WaitFunc, 
        SetCtrl, WaitCtrl, ClearDisp, 
        WaitClear, InitDone, WriteAction, WaitChar, IdleState
    );
    
    type write_fsm_type is (W_Idle, W_Setup, W_Enable);
    type input_state_type is (CheckInput, ProcessInput);

    -- Timing Signals
    signal timer_1ms_tick : std_logic := '0';
    signal div_counter : integer range 0 to 49 := 0;
    signal delay_counter : unsigned(16 downto 0) := (others => '0');
    signal delay_complete : std_logic := '0';

    -- FSM Signals
    signal curr_state : main_fsm_type := PowerOnWait;
    signal next_state : main_fsm_type;
    signal curr_w_state : write_fsm_type := W_Idle;
    signal next_w_state : write_fsm_type;
    
    signal enable_write : std_logic := '0';

    -- Keyboard Signals
    signal read_req : std_logic;
    signal key_data : std_logic_vector(7 downto 0);
    signal kb_buffer_empty : std_logic;
    signal input_fsm : input_state_type := CheckInput;

    -- Game Logic Signals
    signal lives_count : unsigned(3 downto 0) := "0110"; -- Starts with 6 lives
    signal game_finished : std_logic;
    signal correct_mask : std_logic_vector(4 downto 0) := "00000"; -- Bitmask for correct letters
    
    -- LCD Command/Data Buffer
    type lcd_instruction_array is array (integer range 0 to 25) of std_logic_vector(9 downto 0);
    signal lcd_instructions : lcd_instruction_array;
    signal instr_ptr : integer range 0 to lcd_instruction_array'HIGH + 1 := 0;

    -- Word Database (ROM)
    type char_array is array (0 to 4) of std_logic_vector(7 downto 0);
    type word_rom_type is array (0 to 3) of char_array;
    
    -- Words: HIENA, TIGRE, LIVRO, NAVIO
    constant WORD_BANK : word_rom_type := (
        (X"48", X"49", X"45", X"4E", X"41"), 
        (X"54", X"49", X"47", X"52", X"45"), 
        (X"4C", X"49", X"56", X"52", X"4F"), 
        (X"4E", X"41", X"56", X"49", X"4F")  
    );
    
    signal current_word_idx : integer range 0 to 3 := 0;

begin

    -- Instantiate Keyboard Driver
    KB_Driver : Keyboard_Controller 
        PORT MAP(
            clk => CLK, 
            reset => rst, 
            ps2d => ps2d, 
            ps2c => ps2c, 
            rd_command => read_req, 
            ascii_key => key_data, 
            buffer_empty => kb_buffer_empty
        );

    --========================================================================
    -- Process: Clock Divider (Generate 1MHz Tick)
    --========================================================================
    Clock_Div: process (CLK, rst)
    begin
        if rst = '1' then
            div_counter <= 0;
            timer_1ms_tick <= '0';
        elsif rising_edge(CLK) then
            timer_1ms_tick <= '0';
            if div_counter = 49 then
                div_counter <= 0;
                timer_1ms_tick <= '1';
            else
                div_counter <= div_counter + 1;
            end if;
        end if;
    end process;

    --========================================================================
    -- Process: Main Game Logic
    -- Handles key presses, checking matches, and updating game state
    --========================================================================
    Game_Engine: process (CLK, rst)
        variable match_found : boolean;
    begin
        if rst = '1' then
            read_req <= '0';
            lives_count <= "0110"; 
            correct_mask <= "00000";
            input_fsm <= CheckInput;
            current_word_idx <= 0;
            
        elsif rising_edge(CLK) then
            
            case input_fsm is
                when CheckInput =>
                    read_req <= '0';
                    -- Check if keyboard has data
                    if kb_buffer_empty = '0' then
                        read_req <= '1'; -- Acknowledge read
                        tecla <= key_data; -- Debug output
                        
                        -- CASE 1: Game Over / Reset Condition
                        if game_finished = '1' then
                            if key_data = X"0D" then -- User pressed ENTER
                                lives_count <= "0110"; -- Reset Lives
                                correct_mask <= "00000"; -- Reset Mask
                                
                                -- Cycle to next word
                                if current_word_idx = 3 then 
                                    current_word_idx <= 0;
                                else 
                                    current_word_idx <= current_word_idx + 1;
                                end if;
                            end if;

                        -- CASE 2: Gameplay Active
                        else
                            -- Validate input is uppercase letter (A-Z)
                            if (key_data >= X"41" and key_data <= X"5A") then
                                match_found := false;
                                
                                -- Iterate through current word to find matches
                                for i in 0 to 4 loop
                                    if key_data = WORD_BANK(current_word_idx)(i) then
                                        correct_mask(4-i) <= '1'; -- Update mask
                                        match_found := true;
                                    end if;
                                end loop;

                                -- Decrement life if no match found
                                if match_found = false then
                                    if lives_count > 0 then
                                        lives_count <= lives_count - 1;
                                    end if;
                                end if;
                            end if;
                        end if;
                        -- Move to wait state to prevent double reading
                        input_fsm <= ProcessInput;
                    end if;

                when ProcessInput =>
                    read_req <= '0';
                    input_fsm <= CheckInput;
            end case;
        end if;
    end process;

    -- Determine Game Over status (Win or Lose)
    game_finished <= '1' when (lives_count = 0 or correct_mask = "11111") else '0';

    --========================================================================
    -- Process: LCD Content Manager
    -- Updates the instruction buffer based on game state
    --========================================================================
    LCD_Updater: process (game_finished, lives_count, correct_mask, current_word_idx)
    begin
        -- Standard Initialization Commands
        lcd_instructions(0) <= "00" & X"38"; -- 8-bit mode, 2 lines
        lcd_instructions(1) <= "00" & X"0C"; -- Display ON, Cursor OFF
        lcd_instructions(2) <= "00" & X"01"; -- Clear Display
        lcd_instructions(3) <= "00" & X"06"; -- Entry Mode
        lcd_instructions(17) <= "00" & X"C0"; -- Move to second line
        lcd_instructions(23) <= "00" & X"CC"; -- Position for lives
        lcd_instructions(25) <= "00" & X"80"; -- Return Home

        -- Default Header: "JOGO DA FORCA"
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

        -- Game Over Message Logic
        if game_finished = '1' then
            if correct_mask = "11111" then 
                -- "VOCE GANHOU  "
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
            elsif lives_count = 0 then 
                -- "VOCE PERDEU  "
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

        -- Word Display Logic (Underscores or Letters)
        if (correct_mask(4) = '1') then lcd_instructions(18) <= "10" & WORD_BANK(current_word_idx)(0);
        else lcd_instructions(18) <= "10" & X"5F"; end if; -- Underscore
        
        if (correct_mask(3) = '1') then lcd_instructions(19) <= "10" & WORD_BANK(current_word_idx)(1);
        else lcd_instructions(19) <= "10" & X"5F"; end if;
        
        if (correct_mask(2) = '1') then lcd_instructions(20) <= "10" & WORD_BANK(current_word_idx)(2);
        else lcd_instructions(20) <= "10" & X"5F"; end if;
        
        if (correct_mask(1) = '1') then lcd_instructions(21) <= "10" & WORD_BANK(current_word_idx)(3);
        else lcd_instructions(21) <= "10" & X"5F"; end if;
        
        if (correct_mask(0) = '1') then lcd_instructions(22) <= "10" & WORD_BANK(current_word_idx)(4);
        else lcd_instructions(22) <= "10" & X"5F"; end if;

        -- Lives Display
        case (lives_count) is
            when "0110" => lcd_instructions(24) <= "10" & X"36"; -- 6
            when "0101" => lcd_instructions(24) <= "10" & X"35"; -- 5
            when "0100" => lcd_instructions(24) <= "10" & X"34"; -- 4
            when "0011" => lcd_instructions(24) <= "10" & X"33"; -- 3
            when "0010" => lcd_instructions(24) <= "10" & X"32"; -- 2
            when "0001" => lcd_instructions(24) <= "10" & X"31"; -- 1
            when others => lcd_instructions(24) <= "10" & X"30"; -- 0
        end case;
    end process;

    --========================================================================
    -- Process: Delay Timer
    -- Generates delays required by LCD specs
    --========================================================================
    Delay_Timer: process (CLK, rst)
    begin
        if rst = '1' then
            delay_counter <= (others => '0');
        elsif rising_edge(CLK) then
            if timer_1ms_tick = '1' then
                if delay_complete = '1' then
                    delay_counter <= (others => '0');
                else
                    delay_counter <= delay_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- Delay threshold logic
    delay_complete <= '1' when ((curr_state = PowerOnWait and delay_counter >= 40000) or 
                                (curr_state = WaitFunc    and delay_counter >= 100) or   
                                (curr_state = WaitCtrl    and delay_counter >= 100) or  
                                (curr_state = WaitClear   and delay_counter >= 3200) or  
                                (curr_state = WaitChar    and delay_counter >= 80))         
                      else '0';

    --========================================================================
    -- Process: LCD Main FSM
    -- Sequencer for sending commands to LCD
    --========================================================================
    LCD_Main_FSM: process (CLK, rst)
    begin
        if rst = '1' then
            curr_state <= PowerOnWait;
            instr_ptr <= 0;
        elsif rising_edge(CLK) then
             if timer_1ms_tick = '1' then 
                 curr_state <= next_state;
                 
                 if delay_complete = '1' then 
                     case curr_state is
                         when PowerOnWait => instr_ptr <= 0;
                         when WaitFunc    => instr_ptr <= 1;
                         when WaitCtrl    => instr_ptr <= 2;
                         when WaitClear   => instr_ptr <= 3;
                         when WaitChar    => 
                             if instr_ptr = 3 then 
                                 instr_ptr <= 4;
                             elsif instr_ptr = lcd_instruction_array'HIGH then 
                                 instr_ptr <= 4; -- Loop back to start of drawing
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
    LCD_Next_State: process (curr_state, delay_complete, instr_ptr, lcd_instructions) 
    begin
        -- Map current instruction to outputs
        RS <= lcd_instructions(instr_ptr)(9);
        RW <= lcd_instructions(instr_ptr)(8);
        LCD_DB <= lcd_instructions(instr_ptr)(7 downto 0);
        
        enable_write <= '0';
        next_state <= curr_state;

        case curr_state is
            when PowerOnWait => 
                if delay_complete = '1' then next_state <= SetFunc; end if;
            
            when SetFunc => 
                enable_write <= '1'; next_state <= WaitFunc;
            
            when WaitFunc => 
                if delay_complete = '1' then next_state <= SetCtrl; end if;
            
            when SetCtrl => 
                enable_write <= '1'; next_state <= WaitCtrl;
            
            when WaitCtrl => 
                if delay_complete = '1' then next_state <= ClearDisp; end if;
            
            when ClearDisp => 
                enable_write <= '1'; next_state <= WaitClear;
            
            when WaitClear => 
                if delay_complete = '1' then next_state <= InitDone; end if;
            
            when InitDone => 
                next_state <= WriteAction;
            
            when WriteAction => 
                enable_write <= '1'; next_state <= WaitChar;
            
            when WaitChar => 
                if delay_complete = '1' then next_state <= InitDone; end if;
            
            when IdleState => 
                next_state <= IdleState;
        end case;
    end process;
    
    --========================================================================
    -- Process: LCD Write Interface FSM
    -- Generates the 'Enable' pulse
    --========================================================================
    Write_Pulse_FSM: process (CLK, rst)
    begin
        if rst = '1' then
            curr_w_state <= W_Idle;
        elsif rising_edge(CLK) then
             if timer_1ms_tick = '1' then 
                curr_w_state <= next_w_state;
             end if;
        end if;
    end process;

     -- Write Logic flow
     process (curr_w_state, enable_write)
     begin
         next_w_state <= curr_w_state;
         case curr_w_state is
             when W_Idle => 
                 if enable_write = '1' then next_w_state <= W_Setup; end if;
             when W_Setup => 
                 next_w_state <= W_Enable;
             when W_Enable => 
                 next_w_state <= W_Idle;
         end case;
     end process;

     -- Drive the 'E' pin high during the Enable state
     E <= '1' when curr_w_state = W_Enable else '0';
     
end Behavioral;
