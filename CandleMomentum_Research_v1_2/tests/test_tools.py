"""Golden, hand-calculated paths and corrupted exports; no broker required.

These tests validate the Python integrity/replay tools, NOT MQL execution.
Run: python -m unittest discover -s tests -v
"""
import copy
import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from analyze import inspect_run, write_csv, rows, equivalence
from replay_ticks import replay, TARGETS

SCHEMAS = json.loads((ROOT / "tests/schemas.json").read_text())


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.meta = dict(Mode="MODE_RESEARCH", Symbol="EURUSD", Timeframe="PERIOD_M1",
                         FirstTickMsc="120000", LastTickMsc="240000", SignalSequenceFNV1a64="1",
                         InpResearchMinBodyPercent="0.0", Trades="0", Observations="2",
                         CensoredObservations="1", IOFailure="0")
        self.signals = []
        for sid, start, end, reason, mfe, mae in (("a", 120000, 122000, "STOP", 3, 3),
                                                 ("b", 180000, 240000, "CENSORED_HORIZON", 0, 0.2)):
            s = dict.fromkeys(SCHEMAS["ResearchSignals.csv"], "0")
            s.update(RunID="golden", SignalID=sid, Timeframe="PERIOD_M1", SignalTimestamp=str(start//1000-60),
                     EntryBar=str(start//1000), Direction="BUY", Open="1.09982", High="1.10002", Low="1.09982", Close="1.09998",
                     BodyPercent="80", RangePips="2", ATRValid="1", ATRReference="0.0002", ATRPips="2", RangeATR="1",
                     EntryTimeMsc=str(start), ExpectedEntry="1.10002", SL="1.09982", TP="1.10022", SpreadPips="0.2",
                     ExpectedRiskPips="2", CombinedPass="1", PathValid="1", EndReason=reason, EndTimeMsc=str(end),
                     MFE_Pips=str(mfe), MAE_Pips=str(mae), MFE_R=str(mfe/2), MAE_R=str(mae/2))
            s.update(BodyPips="1.6", UpperWickPips="0.4", LowerWickPips="0", BodyPass="1", PipsPass="1", ATRPass="1",
                     RejectReason="SYNTHETIC_NOT_A_BROKER_RUN", MFE_TimeMsc="121000" if sid=="a" else "0",
                     MAE_TimeMsc="122000" if sid=="a" else "180000")
            self.signals.append(s)
        self.levels = []
        for s in self.signals:
            for target in TARGETS:
                outcome = "CENSORED_HORIZON" if s["SignalID"] == "b" else ("TARGET_BEFORE_SL" if target <= 1.5 else "SL_BEFORE_TARGET")
                arrival = "" if s["SignalID"] == "b" else ("121000" if target <= 1.5 else "122000")
                self.levels.append(dict(RunID="golden", SignalID=s["SignalID"], TargetR=str(target), Outcome=outcome,
                                        ArrivalTimeMsc=arrival, ObservationEndTimeMsc=s["EndTimeMsc"]))
        self.summary = []
        for target in TARGETS:
            r = dict.fromkeys(SCHEMAS["ResearchSummary.csv"], "0")
            hits, stops = (1, 0) if target <= 1.5 else (0, 1)
            r.update(RunID="golden", Dimension="ALL", Group="ALL", TargetR=str(target), Total="2", Valid="2",
                     CensoredObservations="1", Hits=str(hits), Stops=str(stops), CensoredForTarget="1", Resolved="1",
                     HitPctResolved=str(hits*100), HitPctAllValid=str(hits*50))
            r.update(MeanMFE_R="0.75", MedianMFE_R="0.75", MeanMAE_R="0.8", MedianMAE_R="0.8",
                     MeanMFE_Pips="1.5", MedianMFE_Pips="1.5", MeanMAE_Pips="1.6", MedianMAE_Pips="1.6", MeanSL_Pips="2")
            self.summary.append(r)
        self.ticks = [dict(TimeMsc=t, Bid=b, Ask=a, Flags=6) for t, b, a in
                      [(120000, 1.1, 1.10002), (121000, 1.10032, 1.10034), (122000, 1.09972, 1.09974),
                       (180000, 1.1, 1.10002), (239999, 1.1, 1.10002), (240000, 1.102, 1.10202)]]
        self.save()

    def save(self):
        write_csv(self.root/"RunMetadata.csv", SCHEMAS["RunMetadata.csv"],
                  [dict(RunID="golden", Key=k, Value=v) for k, v in self.meta.items()])
        for name, data in (("ResearchSignals.csv", self.signals), ("ResearchLevels.csv", self.levels),
                           ("ResearchSummary.csv", self.summary)):
            write_csv(self.root/name, SCHEMAS[name], data)
        write_csv(self.root/"ticks.csv", ["TimeMsc", "Bid", "Ask", "Flags"], self.ticks)

    def tearDown(self):
        self.tmp.cleanup()

    def test_golden_research_integrity(self):
        self.assertEqual(inspect_run(self.root)["Integrity"], "PASS")

    def test_gap_and_exclusive_horizon_replay(self):
        result = replay(self.root, self.root/"ticks.csv")
        self.assertEqual(result["Differences"], 0)
        results = list(rows(self.root/"TickReplayAudit.csv"))
        self.assertAlmostEqual(float(results[0]["MFE_Pips"]), 3)
        self.assertAlmostEqual(float(results[0]["MAE_Pips"]), 3)
        self.assertAlmostEqual(float(results[1]["MFE_Pips"]), 0)  # Huge boundary tick is excluded.

    def test_missing_ticks_detected(self):
        self.ticks = self.ticks[1:]
        self.save()
        self.assertGreater(replay(self.root, self.root/"ticks.csv")["Differences"], 0)

    def test_duplicate_signal_rejected(self):
        self.signals.append(copy.deepcopy(self.signals[0]))
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_missing_level_rejected(self):
        self.levels.pop()
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_censor_not_loss(self):
        self.summary[0]["Stops"] = "1"
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_future_candle_rejected(self):
        self.signals[0]["SignalTimestamp"] = "120"
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_invalid_atr_not_zero(self):
        self.signals[0].update(ATRValid="0", ATRReference="0", ATRPips="0", RangeATR="0")
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_missing_atr_blank_allowed(self):
        self.signals[0].update(ATRValid="0", ATRReference="", ATRPips="", RangeATR="")
        self.save()
        self.assertEqual(inspect_run(self.root)["Integrity"], "PASS")

    def test_non_monotonic_first_passage(self):
        self.levels[1].update(Outcome="SL_BEFORE_TARGET", ArrivalTimeMsc="122000")
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_mfe_cannot_be_negative(self):
        self.signals[0]["MFE_Pips"] = "-1"
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_io_error_rejected(self):
        self.meta["IOFailure"] = "1"
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_malformed_csv_rejected(self):
        with (self.root/"ResearchSignals.csv").open("a") as f: f.write("extra,column\n")
        with self.assertRaises(ValueError): inspect_run(self.root)

    def test_equivalence_and_context(self):
        a = inspect_run(self.root)
        b = copy.deepcopy(a); b["RunID"] = "other"
        c = copy.deepcopy(a); c["FirstTickMsc"] = "999"; c["RunID"] = "different_window"
        equivalence([a, b, c], self.root/"equivalent.csv")
        data = list(rows(self.root/"equivalent.csv"))
        self.assertEqual([r["EquivalentRuns"] for r in data], ["2", "2", "1"])

    def test_no_signals_not_exceptional(self):
        self.signals=[]; self.levels=[]; self.summary=[]
        self.meta.update(Observations="0", CensoredObservations="0")
        self.save()
        self.assertEqual(inspect_run(self.root)["SignalsInCSV"], 0)

    def test_unsorted_ticks_rejected(self):
        self.ticks.reverse(); self.save()
        with self.assertRaises(ValueError): replay(self.root, self.root/"ticks.csv")

    def test_wrong_summary_median_rejected(self):
        self.summary[0]["MedianMFE_R"] = "12"
        self.save()
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def make_trading(self):
        self.meta.update(Mode="MODE_TRADING", Trades="1", Observations="0", CensoredObservations="0")
        self.save()
        (self.root/"ResearchSignals.csv").unlink()
        signal = {k: self.signals[0][k] for k in SCHEMAS["Signals.csv"]}
        write_csv(self.root/"Signals.csv", SCHEMAS["Signals.csv"], [signal])
        self.trade = dict.fromkeys(SCHEMAS["Trades.csv"], "0")
        self.trade.update(RunID="golden", SignalID="a", PositionID="10", EntryTimeMsc="120000", ExitTimeMsc="122000",
                          GrossProfit="100", EntryCommission="-2", ExitCommission="-2", TotalCommission="-4",
                          Swap="-1", Fees="-0.5", NetProfit="94.5", EffectiveRiskMoney="100", NetR="0.945",
                          DealTickets="100|101|102|103", OrderTickets="50|51")
        write_csv(self.root/"Trades.csv", SCHEMAS["Trades.csv"], [self.trade])

    def test_trade_costs_and_partial_deals_one_position(self):
        self.make_trading()
        self.assertEqual(inspect_run(self.root)["TradeCount"], 1)

    def test_trade_spread_double_charge_rejected(self):
        self.make_trading()
        self.trade["NetProfit"] = "90"
        write_csv(self.root/"Trades.csv", SCHEMAS["Trades.csv"], [self.trade])
        with self.assertRaises(AssertionError): inspect_run(self.root)

    def test_duplicate_position_rejected(self):
        self.make_trading()
        write_csv(self.root/"Trades.csv", SCHEMAS["Trades.csv"], [self.trade, self.trade])
        with self.assertRaises(AssertionError): inspect_run(self.root)


if __name__ == "__main__":
    unittest.main()
