import matplotlib.pyplot as plt
from vcdvcd import VCDVCD
import matplotlib
matplotlib.use("Agg")

# ============================================================
# Configuration
# ============================================================

VCD_FILE = "dump.vcd"

START_TIME_MS = 1.3
END_TIME_MS = 1.9

PRIMARY_SIGNAL = "dbg_swift_tb.dbg_cwnd[31:0]"
#SECONDARY_SIGNAL = "dbg_swift_tb.phase"
SECONDARY_SIGNAL = "dbg_swift_tb.rtt[31:0]"

# List signals you want to plot
SIGNALS = [
    "dbg_swift_tb.dbg_cwnd[31:0]",
    "dbg_swift_tb.phase",
    "dbg_swift_tb.rtt[31:0]",
]

PHASE_MAP = {
    0: 0,  # STARTUP
    1: 1,  # COMPUTE
    2: 3,  # SYNC -> top
    3: 2,  # RECOVERY -> below sync
}

if SECONDARY_SIGNAL == "dbg_swift_tb.rtt[31:0]":
    secondary_color = "tab:green"
    secondary_label = "RTT"
else:
    secondary_color = "tab:red"
    secondary_label = "Phase"

# ============================================================
# Load VCD
# ============================================================

vcd = VCDVCD(VCD_FILE)
TIME_SCALE = float(vcd.timescale["factor"]) * 1e3

for sig in vcd.signals:
    print(sig)

# ============================================================
# Plot
# ============================================================

fig, ax1 = plt.subplots(figsize=(12, 5))

# Create second y-axis
ax2 = ax1.twinx()

# Define colors
color_cwnd = "tab:blue"
color_users = "tab:red"
color_rtt = "tab:green"


for signal_name in SIGNALS:

    if signal_name not in vcd.signals:
        print(f"Signal not found: {signal_name}")
        continue

    sig = vcd[signal_name]
    tv = sig.tv

    times = []
    values = []

    for t, v in tv:
        times.append(t*TIME_SCALE)  # Convert to seconds

        try:
            val = int(v, 2)

            # Remap phase ordering
            if signal_name == "dbg_swift_tb.phase": 
                val = PHASE_MAP.get(val, val)

            values.append(val)

        except ValueError:
            values.append(0)

    # Extend final value to end of simulation
    max_time = max(t for sig_name in SIGNALS for t, _ in vcd[sig_name].tv)

    if times[-1] < max_time:
        times.append(max_time*TIME_SCALE)
        values.append(values[-1])

    # Plot congestion window on left axis
    if signal_name == "dbg_swift_tb.dbg_cwnd[31:0]":
        ax1.step(
            times,
            values,
            where="post",
            color=color_cwnd,
            label="Congestion Window",
        )

    elif signal_name == SECONDARY_SIGNAL:
        ax2.step(
            times,
            values,
            where="post",
            color=secondary_color,
            label=secondary_label,
        )


# Left axis styling
ax1.set_xlabel("Time [ms]")
ax1.set_ylabel("Congestion Window Size", color=color_cwnd)
ax1.tick_params(axis="y", labelcolor=color_cwnd)
ax1.grid(True)

if SECONDARY_SIGNAL == "dbg_swift_tb.phase":
    ax2.set_ylabel("Phase", color=secondary_color)
    ax2.tick_params(axis="y", labelcolor=secondary_color)

    ax2.set_yticks([0, 1, 2, 3])
    ax2.set_yticklabels([
        "STARTUP",
        "COMPUTE",
        "RECOVERY",
        "SYNC",
    ])

elif SECONDARY_SIGNAL == "dbg_swift_tb.rtt[31:0]":
    ax2.set_ylabel("RTT", color=secondary_color)
    ax2.tick_params(axis="y", labelcolor=secondary_color)

ax1.set_xlim(START_TIME_MS, END_TIME_MS)

# Optional combined legend
#lines1, labels1 = ax1.get_legend_handles_labels()
#lines2, labels2 = ax2.get_legend_handles_labels()

#ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper left")

plt.tight_layout()
plt.savefig("test_plot13.png", dpi=300, bbox_inches="tight")

print("Saved test_plot13.png")