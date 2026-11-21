# Each component's part of the notebook server's configuration:
# /etc/scidesktop/jupyter_server_config.d/<component>.py, in name order
# (docs/components.md). An image gets a component's part by copying the
# component; it sets nothing for it.
#
# Jupyter reads this folder after /etc/jupyter and before the user's
# ~/.jupyter, so a user's own configuration still has the last word.
import glob

for _part in sorted(glob.glob("/etc/scidesktop/jupyter_server_config.d/*.py")):
    load_subconfig(_part)  # noqa: F821
