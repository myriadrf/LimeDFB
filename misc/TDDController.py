
from litex.gen import LiteXModule
from migen import Signal, If, FSM, NextState, NextValue, ClockDomainsRenamer


# Tiny class to hide generic TDD logic
class TDDController(LiteXModule):
    def __init__(self,
                 width, # Bit-width of the TDD signal array
                 tdd_on_setting, # TDD array value when TDD is high
                 tdd_off_setting, # TDD array value when TDD is low
                 delay_clk_domain="sys" # Clock to use for txant_pre/post fsm
                 ):
        # Helper module to perform TDD control
        self.TDDSignal = Signal(1)
        self.InvertTDDSignal = Signal(1)
        self.Internal_TDDSignal = Signal(1)
        self.ControlEnable = Signal(1)
        self.OutputSignal = Signal(width)
        self.PassthroughSignal = Signal(width)

        self.txant_pre = Signal(16)
        self.txant_post = Signal(16)
        self.counter    = Signal(16)
        self.delayed_tdd = Signal(1)

        self.tdd_on_setting = tdd_on_setting
        self.tdd_off_setting = tdd_off_setting

        self.comb += [
            If(self.InvertTDDSignal == 1,[
                self.Internal_TDDSignal.eq(~self.TDDSignal)
            ]).Else([
                self.Internal_TDDSignal.eq(self.TDDSignal)
            ])
        ]

        fsm = FSM(reset_state="IDLE")
        fsm = ClockDomainsRenamer({"sys": delay_clk_domain})(fsm)
        self.delay_fsm = fsm

        fsm.act("IDLE",[
            NextValue(self.delayed_tdd, 0),
            NextValue(self.counter, 0),
            If(self.Internal_TDDSignal == 1,[
                NextState("RISE_DELAY")
            ])
        ])

        fsm.act("RISE_DELAY",[
            NextValue(self.delayed_tdd, 0),
            If(self.counter >= self.txant_pre,[
                NextState("WAIT_FALL"),
                NextValue(self.counter, 0)
            ]).Else([
                NextValue(self.counter, self.counter + 1)
            ])
        ])

        fsm.act("WAIT_FALL",[
            NextValue(self.delayed_tdd, 1),
            If(self.Internal_TDDSignal == 0,[
                NextState("FALL_DELAY")
            ])
        ])

        fsm.act("FALL_DELAY",[
            NextValue(self.delayed_tdd, 1),
            If(self.counter >= self.txant_post,[
                NextState("IDLE"),
                NextValue(self.counter, 0)
            ]).Else([
                NextValue(self.counter, self.counter + 1)
            ])
        ])

        self.comb += [
            If(self.ControlEnable == 1,[
                If(self.delayed_tdd == 1, [
                    self.OutputSignal.eq(self.tdd_on_setting)
                ]).Else([
                    self.OutputSignal.eq(self.tdd_off_setting)
                ])
            ]).Else([
                self.OutputSignal.eq(self.PassthroughSignal)
            ])
        ]