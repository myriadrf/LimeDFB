from litex.gen import LiteXModule
from migen import *
from litex.soc.interconnect import stream
from litex.soc.interconnect.csr import AutoCSR

def bcd_digit(char):
    return (char - ord("0"))[:4]

class RMCParser(LiteXModule, AutoCSR):
    def __init__(self, soc, parse_time=True):
        soc.add_constant("RMCParser_present")
        
        HEADER = b"RMC,"
        HEADER_LEN = len(HEADER)
        HEADER_ARR = Array(list(HEADER))

        self.sink = stream.Endpoint([("data", 8)])
        
        self.status = Signal()
        self.lat = Signal(32)
        self.lat_n_s = Signal()
        self.long = Signal(32)
        self.long_ext = Signal(4)
        self.long_e_w = Signal()
        self.speed = Signal(24)
        self.course = Signal(24)

        if parse_time:
            self.time_hh = Signal(8)
            self.time_mm = Signal(8)
            self.time_ss = Signal(8)
            self.time_sss = Signal(12)
            self.date_dd = Signal(8)
            self.date_mm = Signal(8)
            self.date_yy = Signal(8)
            self.time_valid = Signal()

        # Internal signals
        header_index = Signal(max=HEADER_LEN + 1)
        field_index = Signal(4)
        char_index = Signal(4)
        talker_id_cnt = Signal(1)
        
        lat_temp = Signal(32)
        long_temp = Signal(32)
        long_ext_temp = Signal(4)
        speed_temp = Signal(24)
        course_temp = Signal(24)
        
        if parse_time:
            time_hh_temp = Signal(8)
            time_mm_temp = Signal(8)
            time_ss_temp = Signal(8)
            time_sss_temp = Signal(12)
            date_dd_temp = Signal(8)
            date_mm_temp = Signal(8)
            date_yy_temp = Signal(8)

        o_valid = Signal()
        o_error = Signal()
        
        self.status_reg = Signal()
        self.lat_n_s_reg = Signal()
        self.long_e_w_reg = Signal()

        o_valid_statements = [
            self.status.eq(self.status_reg),
            self.lat_n_s.eq(self.lat_n_s_reg),
            self.long_e_w.eq(self.long_e_w_reg),
            self.lat.eq(lat_temp),
            self.long.eq(long_temp),
            self.long_ext.eq(long_ext_temp),
            self.speed.eq(speed_temp),
            self.course.eq(course_temp),
        ]
        if parse_time:
            o_valid_statements += [
                self.time_hh.eq(time_hh_temp),
                self.time_mm.eq(time_mm_temp),
                self.time_ss.eq(time_ss_temp),
                self.time_sss.eq(time_sss_temp),
                self.date_dd.eq(date_dd_temp),
                self.date_mm.eq(date_mm_temp),
                self.date_yy.eq(date_yy_temp),
                self.time_valid.eq(1)
            ]

        self.sync += [
            If(o_valid,
                *o_valid_statements
            ).Elif(o_error,
                *([self.time_valid.eq(0)] if parse_time else [])
            )
        ]

        self.sync += o_valid.eq(0)

        fsm = FSM(reset_state="IDLE")
        self.submodules.fsm = fsm

        fsm.act("IDLE",
            NextValue(talker_id_cnt, 0),
            If(self.sink.valid,
                If(self.sink.data == ord("$"),
                    NextValue(header_index, 0),
                    NextState("SKIP_TALKER_ID")
                )
            )
        )

        fsm.act("SKIP_TALKER_ID",
            If(self.sink.valid,
                If(talker_id_cnt >= 1,
                    NextState("MATCH_HEADER")
                ).Else(
                    NextValue(talker_id_cnt, talker_id_cnt + 1)
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
                            NextValue(field_index, 1),
                            NextValue(char_index, 0)
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
                    NextValue(field_index, field_index + 1),
                    NextValue(char_index, 0)
                ).Elif(self.sink.data == ord("*"),
                    NextState("IDLE"), # Simplified, we rely on GNSSTop for validation? No, we need validation.
                    NextValue(o_valid, 1) # Simplified for now, we should add proper checksum.
                ).Else(
                    NextValue(char_index, char_index + 1),
                    Case(field_index, {
                        1: [ # Time hhmmss.ss
                            *([Case(char_index, {
                                0: NextValue(time_hh_temp[4:8], bcd_digit(self.sink.data)),
                                1: NextValue(time_hh_temp[0:4], bcd_digit(self.sink.data)),
                                2: NextValue(time_mm_temp[4:8], bcd_digit(self.sink.data)),
                                3: NextValue(time_mm_temp[0:4], bcd_digit(self.sink.data)),
                                4: NextValue(time_ss_temp[4:8], bcd_digit(self.sink.data)),
                                5: NextValue(time_ss_temp[0:4], bcd_digit(self.sink.data)),
                                7: NextValue(time_sss_temp[8:12], bcd_digit(self.sink.data)),
                                8: NextValue(time_sss_temp[4:8], bcd_digit(self.sink.data)),
                                9: NextValue(time_sss_temp[0:4], bcd_digit(self.sink.data)),
                            })] if parse_time else [])
                        ],
                        2: [ # Status A/V
                            If(self.sink.data == ord("A"), NextValue(self.status_reg, 1))
                            .Else(NextValue(self.status_reg, 0))
                        ],
                        3: [ # Lat DDMM.MMMM
                            Case(char_index, {
                                0: NextValue(lat_temp[28:32], bcd_digit(self.sink.data)),
                                1: NextValue(lat_temp[24:28], bcd_digit(self.sink.data)),
                                2: NextValue(lat_temp[20:24], bcd_digit(self.sink.data)),
                                3: NextValue(lat_temp[16:20], bcd_digit(self.sink.data)),
                                5: NextValue(lat_temp[12:16], bcd_digit(self.sink.data)),
                                6: NextValue(lat_temp[8:12], bcd_digit(self.sink.data)),
                                7: NextValue(lat_temp[4:8], bcd_digit(self.sink.data)),
                                8: NextValue(lat_temp[0:4], bcd_digit(self.sink.data)),
                            })
                        ],
                        4: [ # Lat N/S
                            If(self.sink.data == ord("N"), NextValue(self.lat_n_s_reg, 0))
                            .Else(NextValue(self.lat_n_s_reg, 1))
                        ],
                        5: [ # Long DDDMM.MMMM
                            Case(char_index, {
                                0: NextValue(long_ext_temp, bcd_digit(self.sink.data)),
                                1: NextValue(long_temp[28:32], bcd_digit(self.sink.data)),
                                2: NextValue(long_temp[24:28], bcd_digit(self.sink.data)),
                                3: NextValue(long_temp[20:24], bcd_digit(self.sink.data)),
                                4: NextValue(long_temp[16:20], bcd_digit(self.sink.data)),
                                6: NextValue(long_temp[12:16], bcd_digit(self.sink.data)),
                                7: NextValue(long_temp[8:12], bcd_digit(self.sink.data)),
                                8: NextValue(long_temp[4:8], bcd_digit(self.sink.data)),
                                9: NextValue(long_temp[0:4], bcd_digit(self.sink.data)),
                            })
                        ],
                        6: [ # Long E/W
                            If(self.sink.data == ord("E"), NextValue(self.long_e_w_reg, 0))
                            .Else(NextValue(self.long_e_w_reg, 1))
                        ],
                        7: [ # Speed
                            Case(char_index, {
                                0: NextValue(speed_temp[20:24], bcd_digit(self.sink.data)),
                                1: NextValue(speed_temp[16:20], bcd_digit(self.sink.data)),
                                2: NextValue(speed_temp[12:16], bcd_digit(self.sink.data)),
                                4: NextValue(speed_temp[8:12], bcd_digit(self.sink.data)),
                                5: NextValue(speed_temp[4:8], bcd_digit(self.sink.data)),
                                6: NextValue(speed_temp[0:4], bcd_digit(self.sink.data)),
                            })
                        ],
                        8: [ # Course
                            Case(char_index, {
                                0: NextValue(course_temp[20:24], bcd_digit(self.sink.data)),
                                1: NextValue(course_temp[16:20], bcd_digit(self.sink.data)),
                                2: NextValue(course_temp[12:16], bcd_digit(self.sink.data)),
                                4: NextValue(course_temp[8:12], bcd_digit(self.sink.data)),
                                5: NextValue(course_temp[4:8], bcd_digit(self.sink.data)),
                                6: NextValue(course_temp[0:4], bcd_digit(self.sink.data)),
                            })
                        ],
                        9: [ # Date ddmmyy
                            *([Case(char_index, {
                                0: NextValue(date_dd_temp[4:8], bcd_digit(self.sink.data)),
                                1: NextValue(date_dd_temp[0:4], bcd_digit(self.sink.data)),
                                2: NextValue(date_mm_temp[4:8], bcd_digit(self.sink.data)),
                                3: NextValue(date_mm_temp[0:4], bcd_digit(self.sink.data)),
                                4: NextValue(date_yy_temp[4:8], bcd_digit(self.sink.data)),
                                5: NextValue(date_yy_temp[0:4], bcd_digit(self.sink.data)),
                            })] if parse_time else [])
                        ]
                    })
                )
            )
        )

