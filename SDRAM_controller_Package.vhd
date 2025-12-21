LIBRARY ieee;
USE ieee.std_logic_1164.all;

PACKAGE SDRAM_controller_Package IS
  type StateFSM_type is (Idle, Waiting, Reading, Writing, Activation);
  type StateSubsys_type is (Idle, Ctr_request, Precharge, SetMR, Refresh, ValidOp, Waiting_precharge, Waiting_SetMR, Waiting_refresh);
END SDRAM_controller_Package;
