"""CSV integrity, distributions and equivalent selections. Python 3.10+, stdlib only."""
import argparse
import csv
import hashlib
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


def rows(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or len(set(reader.fieldnames)) != len(reader.fieldnames):
            raise ValueError(f"Invalid header: {path}")
        for line, row in enumerate(reader, 2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError(f"Malformed CSV: {path}:{line}")
            yield row


def number(row, key):
    value = float(row[key])
    if not math.isfinite(value):
        raise ValueError(f"Non-finite {key}")
    return value


def write_csv(path, fields, data):
    with Path(path).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(data)


def inspect_run(directory):
    directory = Path(directory)
    meta_rows = list(rows(directory / "RunMetadata.csv"))
    meta = {r["Key"]: r["Value"] for r in meta_rows}
    assert len(meta) == len(meta_rows), "Duplicate metadata key"
    research = (directory / "ResearchSignals.csv").exists()
    signals = list(rows(directory / ("ResearchSignals.csv" if research else "Signals.csv")))
    ids = {s["SignalID"] for s in signals}
    assert len(ids) == len(signals), "Duplicate signal ID"
    for s in signals:
        assert int(s["SignalTimestamp"]) < int(s["EntryBar"]), "Future candle"
        assert int(s["EntryTimeMsc"]) >= int(s["EntryBar"]) * 1000
        assert number(s, "High") > number(s, "Low")
        assert 0 < number(s, "BodyPercent") <= 100 + 1e-7
        assert math.isclose(number(s, "SL"), number(s, "Low" if s["Direction"] == "BUY" else "High"), abs_tol=1e-9)
        assert math.isclose(number(s, "RangePips"), (number(s, "High")-number(s, "Low"))/0.0001, abs_tol=1e-7)
        if s["ATRValid"] == "0":
            assert s["ATRReference"] == s["ATRPips"] == s["RangeATR"] == ""
        else:
            assert math.isclose(number(s, "RangeATR"), number(s, "RangePips") / number(s, "ATRPips"), rel_tol=1e-7)
    if research:
        by_id = {s["SignalID"]: s for s in signals}
        levels = list(rows(directory / "ResearchLevels.csv"))
        assert len(levels) == 7 * len(signals)
        assert len({(r["SignalID"], r["TargetR"]) for r in levels}) == len(levels)
        grouped = defaultdict(list)
        for r in levels:
            s = by_id[r["SignalID"]]
            grouped[r["SignalID"]].append(r)
            outcome = r["Outcome"]
            assert outcome in {"TARGET_BEFORE_SL", "SL_BEFORE_TARGET", "NOT_EXECUTABLE", "CENSORED_HORIZON", "CENSORED_TEST_END", "CENSORED_DEINIT", "CENSORED_DATA_GAP"}
            if r["ArrivalTimeMsc"]:
                assert int(s["EntryTimeMsc"]) <= int(r["ArrivalTimeMsc"]) <= int(s["EndTimeMsc"])
                assert outcome in {"TARGET_BEFORE_SL", "SL_BEFORE_TARGET"}
            else:
                assert outcome not in {"TARGET_BEFORE_SL", "SL_BEFORE_TARGET"}
        for sid, data in grouped.items():
            data.sort(key=lambda r: float(r["TargetR"]))
            hits = [r["Outcome"] == "TARGET_BEFORE_SL" for r in data]
            assert hits == sorted(hits, reverse=True), f"Non-monotonic hits: {sid}"
            times = [int(r["ArrivalTimeMsc"]) for r in data if r["Outcome"] == "TARGET_BEFORE_SL"]
            assert times == sorted(times)
        for s in signals:
            assert number(s, "MFE_Pips") >= 0 and number(s, "MAE_Pips") >= 0
            if s["PathValid"] == "1":
                assert number(s, "ExpectedRiskPips") > 0
                assert math.isclose(number(s, "MFE_R"), number(s, "MFE_Pips") / number(s, "ExpectedRiskPips"), abs_tol=1e-7)
                assert math.isclose(number(s, "MAE_R"), number(s, "MAE_Pips") / number(s, "ExpectedRiskPips"), abs_tol=1e-7)
        valid_signals = [s for s in signals if s["PathValid"] == "1"]
        all_rows = 0
        for r in rows(directory / "ResearchSummary.csv"):
            valid, hits, stops, censored = (int(r[k]) for k in ("Valid", "Hits", "Stops", "CensoredForTarget"))
            assert hits + stops + censored == valid
            assert int(r["Resolved"]) == hits + stops
            if hits + stops:
                assert math.isclose(float(r["HitPctResolved"]), 100 * hits / (hits + stops), abs_tol=1e-7)
            if valid:
                assert math.isclose(float(r["HitPctAllValid"]), 100 * hits / valid, abs_tol=1e-7)
            if r["Dimension"] == "ALL":
                all_rows += 1
                assert int(r["Total"]) == len(signals) and valid == len(valid_signals)
                subset = [v for v in levels if float(v["TargetR"]) == float(r["TargetR"])]
                assert hits == sum(v["Outcome"] == "TARGET_BEFORE_SL" for v in subset)
                assert stops == sum(v["Outcome"] == "SL_BEFORE_TARGET" for v in subset)
                for raw in ("MFE_R", "MAE_R", "MFE_Pips", "MAE_Pips"):
                    values = [number(s, raw) for s in valid_signals]
                    if values:
                        assert math.isclose(number(r, "Mean"+raw), statistics.mean(values), abs_tol=1e-7)
                        assert math.isclose(number(r, "Median"+raw), statistics.median(values), abs_tol=1e-7)
                if valid:
                    assert math.isclose(number(r, "MeanSL_Pips"), statistics.mean(number(s, "ExpectedRiskPips") for s in valid_signals), abs_tol=1e-7)
        assert all_rows == (7 if signals else 0), "Missing or duplicate ALL summaries"
        assert int(meta["Observations"]) == len(signals)
        assert int(meta["CensoredObservations"]) == sum(s["EndReason"].startswith("CENSORED_") for s in signals)
    else:
        trades = list(rows(directory / "Trades.csv"))
        assert len({r["PositionID"] for r in trades}) == len(trades)
        for t in trades:
            assert t["SignalID"] in ids
            net = sum(number(t, k) for k in ("GrossProfit", "TotalCommission", "Swap", "Fees"))
            assert math.isclose(number(t, "NetProfit"), net, abs_tol=1e-7)
            assert math.isclose(number(t, "TotalCommission"), number(t, "EntryCommission") + number(t, "ExitCommission"), abs_tol=1e-7)
            assert int(t["EntryTimeMsc"]) <= int(t["ExitTimeMsc"])
            assert number(t, "MFE_Pips") >= 0 and number(t, "MAE_Pips") >= 0
            if number(t, "EffectiveRiskMoney") > 0:
                assert math.isclose(number(t, "NetR"), net / number(t, "EffectiveRiskMoney"), abs_tol=1e-7)
        assert int(meta["Trades"]) == len(trades)
    assert meta["IOFailure"] == "0", "EA reported file I/O errors"
    # Sort by stable ID because research observations finish in a different order.
    selected = sorted(s["SignalID"] for s in signals if s["CombinedPass"] == "1")
    digest = hashlib.sha256("\n".join(selected).encode()).hexdigest()
    distributions = []
    for key in ("BodyPercent", "RangePips", "RangeATR"):
        values = sorted(number(s, key) for s in signals if s[key] != "")
        if values:
            # Explicit nearest-rank empirical quantiles, no fitted distribution.
            for p in (0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1):
                value = values[max(0, math.ceil(p * len(values)) - 1)]
                distributions.append(dict(Field=key, Quantile=p, Value=value, Count=len(values)))
    write_csv(directory / "Distributions.csv", ["Field", "Quantile", "Value", "Count"], distributions)
    result = {"RunID": meta_rows[0]["RunID"], "Mode": meta["Mode"], "Symbol": meta["Symbol"],
              "Timeframe": meta["Timeframe"], "FirstTickMsc": meta["FirstTickMsc"], "LastTickMsc": meta["LastTickMsc"],
              "SequenceFNV": meta["SignalSequenceFNV1a64"], "SelectionSHA256": digest,
              "UniverseMinBody": meta["InpResearchMinBodyPercent"], "SignalsInCSV": len(signals),
              "TradeCount": int(meta["Trades"]), "Integrity": "PASS", "Parameters": {k: v for k, v in meta.items() if k.startswith("Inp")}}
    (directory / "Analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def equivalence(results, output):
    groups = defaultdict(list)
    for r in results:
        # Comparing only identical symbol, TF, time window and research universe.
        context = tuple(r[k] for k in ("Mode", "Symbol", "Timeframe", "FirstTickMsc", "LastTickMsc", "UniverseMinBody", "SequenceFNV", "SelectionSHA256"))
        groups[context].append(r)
    records = []
    for n, group in enumerate(groups.values(), 1):
        configurations = {json.dumps(r["Parameters"], sort_keys=True) for r in group}
        for r in group:
            records.append({"Group": n, "RunID": r["RunID"], "EquivalentRuns": len(group), "DistinctConfigurations": len(configurations), "SelectionSHA256": r["SelectionSHA256"], "Trades": r["TradeCount"]})
    write_csv(output, ["Group", "RunID", "EquivalentRuns", "DistinctConfigurations", "SelectionSHA256", "Trades"], records)
    parameter_records = []
    for key in sorted({k for r in results for k in r["Parameters"]}):
        if key in {"InpRunLabel", "InpEnableTelemetry", "InpServerTimezone"}:
            continue
        values = defaultdict(set)
        for r in results:
            values[r["Parameters"].get(key, "")].add(r["SelectionSHA256"])
        for value, selections in values.items():
            parameter_records.append(dict(Parameter=key, Value=value, DistinctSelections=len(selections)))
    write_csv(Path(output).with_name("ParameterSelections.csv"), ["Parameter", "Value", "DistinctSelections"], parameter_records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--equivalence", type=Path, default=Path("EquivalentRuns.csv"))
    args = parser.parse_args()
    results = [inspect_run(path) for path in args.runs]
    equivalence(results, args.equivalence)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
