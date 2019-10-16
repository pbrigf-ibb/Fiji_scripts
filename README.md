# Fiji_scripts
Scripts and macros for Fiji/ImageJ. 


The scripts can be run externally or installed. To run a script, open its file in the script editor, either by dragging its file to the  Fiji main window or opening the editor (by pressing "\[") and opening the script from the File menu there. Once the file is open, press Run (Ctrl+R). To install a script, place it in the plugins directory of your ImageJ application. File names can be changed but an underscore and the extension must remain.

The Library.txt is a way to add custom functions to your ImageJ: simply create a file like it in the macros directory of your installation to be able to access them from any script.

This Library file contains functions that can be used in any script, i.e. they do not depend on any variables other than their arguments.

The scripts depend on the functions defined in the Library file but for the time being all scripts are self-contained: each one defines all the functions it requires. This may change in the future, whereupon the Library file will become necessary.
