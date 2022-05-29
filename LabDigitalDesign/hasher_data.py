import json
import matplotlib.pyplot as plt
from matplotlib import cm
import numpy as np

file = open("log.txt", "r")
content = json.load(file)

fig = plt.figure(figsize=(16, 9))
ax1 = fig.add_subplot(221, projection='3d')
ax2 = fig.add_subplot(222, projection='3d')
ax3 = fig.add_subplot(223, projection='3d')
ax4 = fig.add_subplot(224, projection='3d')
ax1.set_title('Avg. Hashrate (H/s)')
ax2.set_title('Avg. Time (ms)')
ax3.set_title('Avg. Hashrate (H/s)')
ax4.set_title('Avg. Time (ms)')

difficulties = []
blocks = []
data_avg_time = []
data_avg_hashrate = []
for experiment in content:
    # Each experiment has an increasing difficulty
    difficulties.append(experiment["DIFFICULTY"].lower().count("f") * 4)
    blocks = [i + 1 for i in range(len(experiment["BLOCK_EXPERIMENTS"]))]
    for block_exp in (experiment["BLOCK_EXPERIMENTS"]):
        data_avg_time.append(block_exp["avg_time"])
        data_avg_hashrate.append(block_exp["avg_hash_per_sec"])

pass

_xx, _yy = np.meshgrid(difficulties, blocks)
x, y = _xx.ravel(), _yy.ravel()
bottom = np.zeros_like(data_avg_hashrate)
width = difficulties[-1] - difficulties[-2] - 1
depth = 1

for ax in [ax1, ax2, ax3, ax4]:
    ax.xaxis.set_ticks(np.arange(difficulties[0], difficulties[-1] + 1, difficulties[-1] - difficulties[-2]))
    ax.set_xlabel("Difficulty (n. zeros)")
    ax.set_ylabel("N. Blocks")
    ax.yaxis.set_ticks(blocks[::2])

ax1.plot_surface(_xx, _yy, np.array(data_avg_hashrate).reshape((len(blocks), len(difficulties))), cmap=cm.coolwarm,
                       linewidth=0, antialiased=True)

ax2.plot_surface(_xx, _yy, np.array(data_avg_time).reshape((len(blocks), len(difficulties))), cmap=cm.coolwarm,
                 linewidth=0, antialiased=True)

ax3.bar3d(x, y, bottom, width, depth, data_avg_hashrate, shade=True)

ax4.bar3d(x, y, bottom, width, depth, data_avg_time, shade=True)

plt.show()

'''

import numpy as np
import matplotlib.pyplot as plt


# setup the figure and axes
fig = plt.figure(figsize=(8, 3))
ax1 = fig.add_subplot(121, projection='3d')
ax2 = fig.add_subplot(122, projection='3d')

# fake data
_x = np.arange(4)
_y = np.arange(5)
_xx, _yy = np.meshgrid(_x, _y)
x, y = _xx.ravel(), _yy.ravel()

top = x + y
bottom = np.zeros_like(top)
width = depth = 1

ax1.bar3d(x, y, bottom, width, depth, top, shade=True)
ax1.set_title('Shaded')

ax2.bar3d(x, y, bottom, width, depth, top, shade=False)
ax2.set_title('Not Shaded')

plt.show()


'''
