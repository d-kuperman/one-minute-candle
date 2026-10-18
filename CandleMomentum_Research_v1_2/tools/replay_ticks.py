"""Retrospective executable-quote replay of research CSVs (stdlib only).

Input ticks must cover every observation and come from the same server/history.
Equal-millisecond duplicate entry quotes are flagged as ambiguous.
No account P&L is constructed. Large files are read once in chronological order.
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path
from analyze import rows, write_csv

TARGETS = (0.5, 1, 1.5, 2, 3, 4, 5)


def replay(run, ticks_path):
    signals = [s for s in rows(run / "ResearchSignals.csv") if s["PathValid"] == "1"]
    signals.sort(key=lambda s: int(s["EntryTimeMsc"]))
    expected = {(r["SignalID"], float(r["TargetR"])): r for r in rows(run / "ResearchLevels.csv")}
    waiting, active, results = 0, [], []
    last_time = -1

    def finish(item, coverage):
        s = item["s"]
        diffs = []
        if abs(item["mfe"] - float(s["MFE_Pips"])) > 1e-6:
            diffs.append("MFE")
        if abs(item["mae"] - float(s["MAE_Pips"])) > 1e-6:
            diffs.append("MAE")
        if item["entry_matches"] == 0:
            diffs.append("ENTRY_QUOTE_MISSING")
        for level, state in zip(TARGETS, item["state"]):
            recorded = expected[s["SignalID"], level]["Outcome"]
            outcome = state or s["EndReason"]
            if outcome != recorded:
                diffs.append(f"LEVEL_{level}")
        results.append(dict(SignalID=s["SignalID"], MFE_Pips=item["mfe"], MAE_Pips=item["mae"],
                            Differences="|".join(diffs), Coverage=coverage,
                            EntryTimestampAmbiguous=int(item["entry_matches"] > 1), HistoricalTicks=item["count"]))

    for tick in rows(ticks_path):
        msc, bid, ask = int(tick["TimeMsc"]), float(tick["Bid"]), float(tick["Ask"])
        if msc < last_time:
            raise ValueError("Tick export is not chronological")
        last_time = msc
        if bid <= 0 or ask < bid:
            continue
        while waiting < len(signals) and int(signals[waiting]["EntryTimeMsc"]) <= msc:
            s = signals[waiting]
            active.append(dict(s=s, mfe=0.0, mae=0.0, state=[None]*7, count=0, entry_matches=0, started=False, stopped=False))
            waiting += 1
        keep = []
        for item in active:
            s = item["s"]
            end = int(s["EndTimeMsc"])
            exclusive = s["EndReason"] in {"CENSORED_HORIZON", "CENSORED_DATA_GAP"}
            if msc > end or (exclusive and msc == end):
                finish(item, "INTERVAL_PRESENT")
                continue
            side = 1 if s["Direction"] == "BUY" else -1
            entry = float(s["ExpectedEntry"])
            if msc == int(s["EntryTimeMsc"]):
                entry_quote = ask if side == 1 else bid
                spread = (ask-bid)/0.0001
                if abs(entry_quote-entry) < 1e-9 and abs(spread-float(s["SpreadPips"])) < 1e-6:
                    item["entry_matches"] += 1
                    item["started"] = True
            if not item["started"] or item["stopped"]:
                keep.append(item)
                continue
            close = bid if side == 1 else ask
            move = side*(close-entry)/0.0001
            item["mfe"] = max(item["mfe"], move)
            item["mae"] = max(item["mae"], -move)
            item["count"] += 1
            stop = side*(close-float(s["SL"])) <= 1e-10
            r = float(s["ExpectedRiskPips"])
            for k, level in enumerate(TARGETS):
                if item["state"][k] is None:
                    if stop:
                        item["state"][k] = "SL_BEFORE_TARGET"
                    elif move + 1e-6 >= level*r:
                        item["state"][k] = "TARGET_BEFORE_SL"
            item["stopped"] = stop
            keep.append(item)
        active = keep
    for item in active:
        finish(item, "INTERVAL_PRESENT" if last_time >= int(item["s"]["EndTimeMsc"]) else "TICK_EXPORT_END")
    for s in signals[waiting:]:
        results.append(dict(SignalID=s["SignalID"], MFE_Pips="", MAE_Pips="", Differences="NO_TICKS", Coverage="MISSING", EntryTimestampAmbiguous=0, HistoricalTicks=0))
    output = run / "TickReplayAudit.csv"
    write_csv(output, ["SignalID", "MFE_Pips", "MAE_Pips", "Differences", "Coverage", "EntryTimestampAmbiguous", "HistoricalTicks"], results)
    return {"Observations": len(results), "Differences": sum(bool(r["Differences"]) for r in results),
            "CoverageWarnings": sum(r["Coverage"] != "INTERVAL_PRESENT" for r in results), "Output": str(output)}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("run", type=Path)
    p.add_argument("ticks", type=Path)
    a = p.parse_args()
    print(json.dumps(replay(a.run, a.ticks), indent=2))
