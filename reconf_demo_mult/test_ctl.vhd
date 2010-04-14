-------------------------------------------------------------------------------
-- Title      : Test controller
-- Project    : reconf_demo_mult
-------------------------------------------------------------------------------
-- File       : test_ctl.vhd
-- Author     : Pavel Sorejs <sorejs@gmail.com>
-- Company    : 
-- Created    : 2010-01-18
-- Last update: 2010-01-18
-- Platform   : 
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: Comunicates through RS232
-------------------------------------------------------------------------------
-- Copyright (c) 2010 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2010-01-18  1.0      pavel	Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.STD_LOGIC_UNSIGNED.all;
use work.reconf_demo_mult_components.all;

-------------------------------------------------------------------------------

entity test_ctl is

    generic (
        REG_COUNT : integer := 1);      -- count of registers

    port (
        clk       : in std_logic;
        rst       : in std_logic;

        registers_in : in std_logic_vector((REG_COUNT-1)*8 + 7 downto 0);
        registers_out : out std_logic_vector((REG_COUNT-1)*8 + 7 downto 0);

        writeData : out  std_logic_vector(7 downto 0);
        write     : out  std_logic;
        unitBussy : in std_logic;

        readData    : in std_logic_vector(7 downto 0);
        read        : out  std_logic;
        dataPresent : in std_logic
    );

end test_ctl;

-------------------------------------------------------------------------------

architecture str of test_ctl is

    type comm_states is (idle, command, address, send, receive);

    signal ctl_state : comm_states;
    signal next_ctl_state : comm_states;

    signal last_command : std_logic_vector(7 downto 0);
    signal last_register : std_logic_vector(7 downto 0);
    
    signal command_wen : std_logic;
    signal address_wen: std_logic;
    signal register_wen: std_logic;
    
    signal reg_data : std_logic_vector(7 downto 0);

begin  -- str

    -- purpose: Input register multiplexor
    -- type   : combinational
    -- inputs : register_in
    -- outputs: 
    inp_reg_mux: process (last_register, registers_in)
        variable outputvar : std_logic_vector(7 downto 0);
    begin  -- process inp_reg_mux
        outputvar := (others => '0');
        for i in 1 to REG_COUNT loop
            if last_register = i-1 then
                outputvar := registers_in((i-1)*8+7 downto (i-1)*8);
            end if;            
        end loop;  -- i

        reg_data <= outputvar;
    end process inp_reg_mux;

    -- purpose: Generates nex state for FSM
    -- type   : combinational
    -- inputs : ctl_state
    -- outputs: 
    ctl_output: process (ctl_state, dataPresent, last_command, reg_data,
                         unitBussy)
    begin  -- process ctl_output
        case ctl_state is
            when idle =>
                if dataPresent = '1' then
                    read <=  '1';
                    command_wen <=  '1';
                else
                    read <=  '0';
                    command_wen <=  '0';
                end if;
                register_wen <=  '0';
                address_wen <=  '0';                        
                write <=   '0';
                writeData <= (others => '0');
            when command =>
                if last_command = X"45" then
                    writeData <=  X"45";
                    write <=  '1';
                else
                    writeData <= (others => '0');
                    write <= '0';
                end if;
                register_wen <= '0';
                address_wen <=  '0';                
                command_wen <= '0';
                read <=  '0';
            when address =>
                if dataPresent = '1' then
                    read <=  '1';
                    address_wen <=  '1';
                else
                    read <=  '0';
                    address_wen <=  '0';
                end if;
                write <= '0';
                writeData <= (others => '0');
                command_wen <= '0';
                register_wen <=  '0';
            when send =>
                if unitBussy = '0' then
                    write <=  '1';
                else
                    write <=  '0';
                end if;
                writeData <= reg_data;
                read <=  '0';
                register_wen <=  '0';
                address_wen <=  '0';                
                command_wen <= '0';
            when receive =>
                if dataPresent = '1' then
                    read <= '1';
                    register_wen <= '1';
                else
                    read <= '0';
                    register_wen <= '0';
                end if;
                write <=  '0';                
                writeData <= (others => '0');
                address_wen <=  '0';                
                command_wen <= '0';
        end case;
    end process ctl_output;

    -- purpose: Next state of FSM
    -- type   : combinational
    -- inputs : 
    -- outputs: 
    ctl_nextstate: process (ctl_state, dataPresent, last_command, readData,
                            unitBussy)
    begin  -- process ctl_nextstate
        case ctl_state is
            when idle =>
                if dataPresent = '1' then
                    next_ctl_state <= command;
                else
                    next_ctl_state <= idle;
                end if;
            when command =>
                if readData = X"45" then
                    next_ctl_state <= idle;
                elsif readData = X"52" then
                    next_ctl_state <= address;
                elsif readData = X"57" then
                    next_ctl_state <= address;
                else
                    next_ctl_state <= idle;
                end if;
            when address =>
                if dataPresent = '1' then
                    if last_command = X"52" then
                        next_ctl_state <= send;
                    else
                        next_ctl_state <= receive;
                    end if;
                else
                    next_ctl_state <= address;
                end if;
            when send =>
                if unitBussy = '1' then
                    next_ctl_state <= send;
                else
                    next_ctl_state <= idle;
                end if;
            when receive =>
                if dataPresent = '1' then
                    next_ctl_state <= idle;
                else
                    next_ctl_state <= receive;
                end if;
        end case;
    end process ctl_nextstate;

    -- purpose: registers
    -- type   : sequential
    -- inputs : clk, rst
    -- outputs: 
    ctl_regs: process (clk, rst)
    begin  -- process ctl_regs
        if rst = '1' then               -- asynchronous reset (active high)
            last_command <= (others => '0');
            last_register <= (others => '0');
            ctl_state <= idle;
            registers_out <= (others => '0');
        elsif clk'event and clk = '1' then  -- rising clock edge
            ctl_state <= next_ctl_state;
            
            if address_wen = '1' then
                last_register <= readData;
            end if;

            if command_wen = '1' then
                last_command <= readData;
            end if;

            if register_wen = '1' then
                for i in 1 to REG_COUNT loop
                    if last_register = i-1 then
                        registers_out((i-1)*8 + 7 downto (i-1)*8) <= readData;
                    end if;
                end loop;  -- i
           end if;
        end if;
    end process ctl_regs;

end str;

-------------------------------------------------------------------------------
