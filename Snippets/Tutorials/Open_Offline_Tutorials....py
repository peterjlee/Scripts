# @Context context
# @String(label="Tutorial", choices={"Python", "BeanShell"}) choice


import os, java.io.File, bar.Utils
from bar import Utils
from org.scijava.ui.swing.script import TextEditor

# Specify the directory containing the files to be opened
dir = Utils.getSnippetsDir() + "Tutorials" + os.sep

# Specify the extension of the files to be opened
ext = ".py" if choice == "Python" else ".bsh"

# If directory exists, create a new Script Editor window
# and open each filtered file on a dedicated tab
if Utils.fileExists(dir):
    editor = TextEditor(context)
    for (root, dirnames, filenames) in os.walk(dir):
        for filename in filenames:
            if "_" not in filename and filename.endswith(ext):
                path = os.path.join(root, filename)
                editor.open(java.io.File(path))

    # Select first tab, rename editor's window and display it
    editor.switchTo(0)
    editor.setVisible(True)
    editor.setTitle("BAR Tutorial Files" + choice)
