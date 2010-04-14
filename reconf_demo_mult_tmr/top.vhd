-------------------------------------------------------------------------------
-- Title      : TOP Entity
-- Project    : reconf_demo_mult
-------------------------------------------------------------------------------
-- File       : top.vhd
-- Author     : Pavel Sorejs <sorejs@gmail.com>
-- Company    : 
-- Created    : 2010-01-18
-- Last update: 2010-02-01
-- Platform   : 
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2010 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2010-01-18  1.0      pavel	Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.reconf_demo_mult_components.all;

-------------------------------------------------------------------------------

entity top is

    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        serialIn  : in  std_logic;
        serialOut : out std_logic);

end top;

-------------------------------------------------------------------------------

architecture str of top is

    signal registers_in  : std_logic_vector(15 downto 0);
    signal registers_out : std_logic_vector(15 downto 0);
    signal writeData     : std_logic_vector(7 downto 0);
    signal write         : std_logic;
    signal unitBussy     : std_logic;
    signal readData      : std_logic_vector(7 downto 0);
    signal read          : std_logic;
    signal dataPresent   : std_logic;

    signal output1 : std_logic_vector(15 downto 0);
    signal output2 : std_logic_vector(15 downto 0);
    signal output3 : std_logic_vector(15 downto 0);

    attribute keep : string;
    attribute keep of output1: signal is "true";
    attribute keep of output2: signal is "true";
    attribute keep of output3: signal is "true"; 

begin  -- str

    test_ctl_1: test_ctl
       generic map (
            REG_COUNT => 2)
        port map (
            clk           => clk,
            rst           => rst,
            registers_in  => registers_in,
            registers_out => registers_out,
            writeData     => writeData,
            write         => write,
            unitBussy     => unitBussy,
            readData      => readData,
            read          => read,
            dataPresent   => dataPresent);

    UART_VHDL_1: UART_VHDL
        generic map (
            sysfreq  => 50000000,
            baudrate => 115200)
        port map (
            clk         => clk,
            rst         => rst,
            writeData   => writeData,
            write       => write,
            unitBussy   => unitBussy,
            readData    => readData,
            read        => read,
            dataPresent => dataPresent,
            serialIn    => serialIn,
            serialOut   => serialOut);

    datapath_1: datapath
        port map (
            inputA => registers_out(7 downto 0),
            inputB => registers_out(15 downto 8),
            output => output1);

    datapath_2: datapath
        port map (
            inputA => registers_out(7 downto 0),
            inputB => registers_out(15 downto 8),
            output => output2);

    datapath_3: datapath
        port map (
            inputA => registers_out(7 downto 0),
            inputB => registers_out(15 downto 8),
            output => output3);
    
    registers_in <= (output1 and output2) or (output2 and output3) or (output1 and output3);
    
    
end str;

-------------------------------------------------------------------------------
