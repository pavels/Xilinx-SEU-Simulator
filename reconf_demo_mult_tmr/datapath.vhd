-------------------------------------------------------------------------------
-- Title      : Simple demo data path
-- Project    : reconf_demo_simple
-------------------------------------------------------------------------------
-- File       : datapath.vhd
-- Author     : Pavel Sorejs <sorejs@gmail.com>
-- Company    : 
-- Created    : 2009-10-05
-- Last update: 2010-01-18
-- Platform   : 
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2009 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2009-10-05  1.0      pavel	Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

-------------------------------------------------------------------------------

entity datapath is

    port (
        inputA  : in  std_logic_vector(7 downto 0);
        inputB  : in  std_logic_vector(7 downto 0);

        output : out std_logic_vector(15 downto 0));
	 
	 attribute mult_style: string;
	 attribute mult_style of output:signal is "lut";	
	 
end datapath;

-------------------------------------------------------------------------------

architecture str of datapath is
	 
begin  -- str

	output <= inputA * inputB;


end str;

-------------------------------------------------------------------------------
