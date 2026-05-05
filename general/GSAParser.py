from litex.gen import LiteXModule
from migen import *
from litex.soc.interconnect import stream
from litex.soc.interconnect.csr import AutoCSR

class GSAParser(LiteXModule, AutoCSR):
    def __init__(self, soc):
        soc.add_constant("GSAParser_present")
        
        HEADER = b"GSA,"
        HEADER_LEN = len(HEADER)
        HEADER_ARR = Array(list(HEADER))

        self.sink = stream.Endpoint([("data", 8)])
        self.fix_status = Signal(16)

        # Internal signals
        talker_id = Signal(16)
        talker_id_cnt = Signal(1)
        header_index = Signal(max=HEADER_LEN + 1)
        field_index = Signal(5)
        
        fsm = FSM(reset_state="IDLE")
        self.submodules.fsm = fsm

        fsm.act("IDLE",
            NextValue(talker_id_cnt, 0),
            If(self.sink.valid,
                If(self.sink.data == ord("$"),
                    NextState("CAPTURE_TALKER_ID")
                )
            )
        )

        fsm.act("CAPTURE_TALKER_ID",
            If(self.sink.valid,
                If(talker_id_cnt == 0,
                    NextValue(talker_id[8:16], self.sink.data),
                    NextValue(talker_id_cnt, 1)
                ).Else(
                    NextValue(talker_id[0:8], self.sink.data),
                    NextState("MATCH_HEADER"),
                    NextValue(header_index, 0)
                )
            )
        )

        fsm.act("MATCH_HEADER",
            If(self.sink.valid,
                If(header_index < HEADER_LEN,
                    If(self.sink.data == HEADER_ARR[header_index],
                        NextValue(header_index, header_index + 1),
                        If(header_index == HEADER_LEN - 1,
                            NextState("PARSE_FIELDS"),
                            NextValue(field_index, 1)
                        )
                    ).Else(
                        NextState("IDLE")
                    )
                )
            )
        )

        fsm.act("PARSE_FIELDS",
            If(self.sink.valid,
                If(self.sink.data == ord(","),
                    NextValue(field_index, field_index + 1)
                ).Elif(self.sink.data == ord("*"),
                    NextState("IDLE")
                ).Else(
                    If(field_index == 2, # Fix type
                        If((self.sink.data >= ord("1")) & (self.sink.data <= ord("3")),
                            If(talker_id == 0x4750, # GP
                                NextValue(self.fix_status[4:8], self.sink.data - ord("0"))
                            ).Elif(talker_id == 0x474c, # GL
                                NextValue(self.fix_status[0:4], self.sink.data - ord("0"))
                            ).Elif(talker_id == 0x4741, # GA
                                NextValue(self.fix_status[12:16], self.sink.data - ord("0"))
                            ).Elif((talker_id == 0x4742) | (talker_id == 0x4244), # GB or BD
                                NextValue(self.fix_status[8:12], self.sink.data - ord("0"))
                            )
                        )
                    )
                )
            )
        )
