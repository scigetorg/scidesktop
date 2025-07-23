import os
import subprocess

c.ServerProxy.servers = {
  'scidesktop': {
    'command': ['/opt/scidesktop/guacamole.sh'],
    'port': 8080,
    'timeout': 60,
      'request_headers_override': {
          'Authorization': 'Basic am92eWFuOnBhc3N3b3Jk',
      },
      'launcher_entry': {
        'path_info' : 'scidesktop',
        'title': 'scidesktop',
        'icon_path': '/opt/neurodesk_brain_logo.svg'
      }
    }
}
# c.ServerApp.root_dir = '/' # this causes an error when clicking on the little house icon when being located in the home directory
c.ServerApp.preferred_dir = os.getcwd()
c.FileContentsManager.allow_hidden = True

before_notebook = subprocess.call("/opt/scidesktop/jupyterlab_startup.sh")
