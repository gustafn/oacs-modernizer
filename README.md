# oacs-modernizer
Modernize OpenACS packages

Script to change deprecated calls. Do NOT blindly trust this script,
but use it as a helper.

When the script is run, it checks all "*tcl" files in the current
directory tree and replaces deprecated calls with non-deprecated
ones. The original files are preserved with a "-original" suffix.

# Basic Usage:
  - change to the package, you want to modernize
  - run ``tclsh oacs-modernizer.tcl``
 
# Slightly Advanced usage:
  - List the differences  
       ``tclsh oacs-modernizer.tcl -diff 1``

  - Undo tue changes of a run  
       ``tclsh oacs-modernizer.tcl -reset 1 -change 0``

  - Reset the changes and run the script again  
       ``tclsh oacs-modernizer.tcl -reset 1``

  - Remove the -original files after a run to avoid name clashes  
       ``rm `find . -name \*original` ``
