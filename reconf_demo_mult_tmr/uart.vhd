-------------------------------------------------------------------------------
-- Title      : UART RX/TX
-- Project    : GNSS-300
-------------------------------------------------------------------------------
-- File       : uart.vhd
-- Author     : Pavel Sorejs <sorejs@gmail.com>
-- Company    : 
-- Created    : 2009-03-21
-- Last update: 2009-05-14
-- Platform   : 
-- Standard   : VHDL'87
-------------------------------------------------------------------------------
-- Description:
-------------------------------------------------------------------------------
-- Copyright (c) 2009 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2009-03-21  1.0      pavel   Created
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;


entity UART_VHDL is
    generic (
        sysfreq  : integer := 50000000;  -- 50 MHz default
        baudrate : integer := 115200);   -- 115200 bps default
    port (
        clk : in std_logic;
        rst : in std_logic;

        writeData : in  std_logic_vector(7 downto 0);
        write     : in  std_logic;
        unitBussy : out std_logic;

        readData    : out std_logic_vector(7 downto 0);
        read        : in  std_logic;
        dataPresent : out std_logic;

        serialIn  : in  std_logic;
        serialOut : out std_logic
    );
end UART_VHDL;




architecture str of UART_VHDL is

    type t_TxState is (IDLE, START, SEND, STOP);
    type t_RxState is (IDLE, START, RECEIVE, STOP, FULL);

    constant ClkDivTop : integer := sysfreq / baudrate;

    signal clk_div_tx  : integer range 0 to ClkDivTop;
    signal clk_en_tx   : std_logic;
    signal clk_tx_sync : std_logic;

    signal clk_div_rx  : integer range 0 to ClkDivTop;
    signal clk_en_rx   : std_logic;
    signal clk_rx_sync : std_logic;


    signal RxBitCount : std_logic_vector(2 downto 0);
    signal TxBitCount : std_logic_vector(2 downto 0);

    signal TxState     : t_TxState;
    signal RxState     : t_RxState;
    signal nextTxState : t_TxState;
    signal nextRxState : t_RxState;

    signal Tx      : std_logic_vector(7 downto 0);
    signal TxShift : std_logic;

    signal Rx      : std_logic_vector(7 downto 0);
    signal RxShift : std_logic;
    signal RxReset : std_logic;

    signal serialInReg : std_logic;
begin

    readData <= Rx;

    -- purpose: Baudrate clock divider
    -- type   : sequential
    -- inputs : clk,rst
    -- outputs: 
    clockDividerTx : process (clk, rst)
    begin  -- process clockDivider
        if rst = '1' then                   -- asynchronous reset (active high)
            clk_div_tx <= 0;
            clk_en_tx  <= '0';
        elsif clk'event and clk = '1' then  -- rising clock edge
            if clk_tx_sync = '1' then
                clk_div_tx <= 0;
                clk_en_tx  <= '0';
            else
                if clk_div_tx < ClkDivTop then
                    clk_div_tx <= clk_div_tx + 1;
                    clk_en_tx  <= '0';
                else
                    clk_div_tx <= 0;
                    clk_en_tx  <= '1';
                end if;
            end if;
        end if;
    end process clockDividerTx;

    clockDividerRx : process (clk, rst)
    begin  -- process clockDividerRx
        if rst = '1' then                   -- asynchronous reset (active high)
            clk_div_rx <= 0;
            clk_en_rx  <= '0';
        elsif clk'event and clk = '1' then  -- rising clock edge
            if clk_rx_sync = '1' then
                clk_div_rx <= ClkDivTop / 2;
                clk_en_rx  <= '0';
            else
                if clk_div_rx < ClkDivTop then
                    clk_div_rx <= clk_div_rx + 1;
                    clk_en_rx  <= '0';
                else
                    clk_div_rx <= 0;
                    clk_en_rx  <= '1';
                end if;
            end if;
        end if;
    end process clockDividerRx;


    -- purpose: TX next state
    -- type   : combinational
    -- inputs : TxState,TxBitCount,write
    -- outputs: 
    tx_nextstate : process (TxBitCount, TxState, clk_en_tx, write)
    begin  -- process tx_nextstate
        case TxState is
            when IDLE =>
                if write = '1' then
                    nextTxState <= START;
                else
                    nextTxState <= IDLE;
                end if;
            when START =>
                if clk_en_tx = '1' then
                    nextTxState <= SEND;
                else
                    nextTxState <= START;
                end if;
            when SEND =>
                if TxBitCount = 7 and clk_en_tx = '1' then
                    nextTxState <= STOP;
                else
                    nextTxState <= SEND;
                end if;
            when STOP =>
                if clk_en_tx = '1' then
                    nextTxState <= IDLE;
                else
                    nextTxState <= STOP;
                end if;
        end case;
    end process tx_nextstate;

    -- purpose: TX outputs
    -- type   : combinational
    -- inputs : TxState,TxBitCount,writeData,Tx
    -- outputs: 
    tx_output : process (Tx(0), TxState)
    begin  -- process tx_output
        case TxState is
            when IDLE =>
                serialOut   <= '1';
                unitBussy   <= '0';
                clk_tx_sync <= '1';
                TxShift     <= '0';
            when START =>
                serialOut   <= '0';
                unitBussy   <= '1';
                clk_tx_sync <= '0';
                TxShift     <= '0';
            when SEND =>
                serialOut   <= Tx(0);
                unitBussy   <= '1';
                clk_tx_sync <= '0';
                TxShift     <= '1';
            when STOP =>
                serialOut   <= '1';
                unitBussy   <= '1';
                clk_tx_sync <= '0';
                TxShift     <= '0';
        end case;
    end process tx_output;

    -- purpose: TX registers
    -- type   : sequential
    -- inputs : clk, rst
    -- outputs: 
    tx_regs : process (clk, rst)
    begin  -- process tx_regs
        if rst = '1' then                   -- asynchronous reset (active high)
            Tx         <= (others => '0');
            TxBitCount <= (others => '0');
            TxState    <= IDLE;
        elsif clk'event and clk = '1' then  -- rising clock edge
            TxState <= nextTxState;
            if write = '1' then
                Tx <= writeData;
            elsif clk_en_tx = '1' and TxShift = '1' then
                TxBitCount <= TxBitCount + 1;
                Tx         <= '0' & Tx(7 downto 1);
            end if;
        end if;
    end process tx_regs;

    -- purpose: RX next state
    -- type   : combinational
    -- inputs : RxState,RxBitCount,read,serialInReg
    -- outputs: 
    rx_nextstate : process (RxBitCount, RxState, clk_en_rx, read, serialInReg)
    begin  -- process rx_nextstate
        case RxState is
            when IDLE =>
                if serialInReg = '0' then
                    nextRxState <= START;
                else
                    nextRxState <= IDLE;
                end if;
            when START =>
                if serialInReg = '0' and clk_en_rx = '1' then  -- start bit
                    nextRxState <= RECEIVE;
                else
                    if serialInReg = '0' then
                        nextRxState <= START;
                    else
                        nextRxState <= IDLE;  -- No Start Bit = Sync Error
                    end if;
                end if;
            when RECEIVE =>
                if clk_en_rx = '1' then
                    if RxBitCount = 7 then
                        nextRxState <= STOP;
                    else
                        nextRxState <= RECEIVE;
                    end if;
                else
                    nextRxState <= RECEIVE;
                end if;
            when STOP =>
                if clk_en_rx = '1' then
                    if serialInReg /= '1' then                 -- stop bit
                        nextRxState <= IDLE;
                    else
                        nextRxState <= FULL;
                    end if;
                else
                    nextRxState <= STOP;
                end if;
            when FULL =>
                if read = '1' then
                    nextRxState <= IDLE;
                else
                    nextRxState <= FULL;
                end if;
        end case;
    end process rx_nextstate;

    -- purpose: Rx output
    -- type   : combinational
    -- inputs : RxState,RxBitCount,read,serialInReg,Rx
    -- outputs: 
    rx_output : process (RxState, serialInReg)
    begin  -- process rx_output
        case RxState is
            when IDLE =>
                dataPresent <= '0';
                if serialInReg = '0' then
                    clk_rx_sync <= '1';
                else
                    clk_rx_sync <= '0';
                end if;
                RxShift <= '0';
                RxReset <= '1';
            when START =>
                dataPresent <= '0';
                clk_rx_sync <= '0';
                RxShift     <= '0';
                RxReset     <= '0';
            when RECEIVE =>
                dataPresent <= '0';
                clk_rx_sync <= '0';
                RxShift     <= '1';
                RxReset     <= '0';
            when STOP =>
                dataPresent <= '0';
                clk_rx_sync <= '0';
                RxShift     <= '0';
                RxReset     <= '0';
            when FULL =>
                dataPresent <= '1';
                clk_rx_sync <= '0';
                RxShift     <= '0';
                RxReset     <= '0';
        end case;
    end process rx_output;

    -- purpose: Rx registers
    -- type   : sequential
    -- inputs : clk, rst
    -- outputs: 
    rx_regs : process (clk, rst)
    begin  -- process rx_regs
        if rst = '1' then                   -- asynchronous reset (active high)
            RxBitCount  <= (others => '0');
            Rx          <= (others => '0');
            serialInReg <= '1';
            RxState     <= IDLE;
        elsif clk'event and clk = '1' then  -- rising clock edge
            if clk_en_rx = '1' then
                if RxReset = '1' then
                    RxBitCount <= (others => '0');
                    Rx         <= (others => '0');
                elsif RxShift = '1' then
                    RxBitCount <= RxBitCount + 1;
                    Rx         <= serialInReg & Rx(7 downto 1);
                end if;
            end if;

            serialInReg <= serialIn;
            RxState     <= nextRxState;
        end if;
    end process rx_regs;

end str;
