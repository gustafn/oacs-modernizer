#!/usr/bin/env tclsh
# Script to change deprecated calls. Do NOT blindly trust this script,
# but use it as a helper.
#
# When the script is run, it checks all "*tcl" files in the current
# directory tree and replaces deprecated calls with non-deprecated
# ones. The original files are preserved with a "-original" suffix.
#
# Basic Usage:
#  - change to the package, you want to modernize
#  - run "tclsh oacs-modernizer.tcl"
# 
# Slightly Advanced usage:
#  - List the differences 
#       tclsh oacs-modernizer.tcl -diff 1
#
#  - Undo tue changes of a run
#       tclsh oacs-modernizer.tcl -reset 1 -change 0
#
#  - Reset the changes and run the script again
#       tclsh oacs-modernizer.tcl -reset 1
#
#  - Remove the -original files after a run to avoid name clashes
#       rm `find . -name \*original`
#
# Gustaf Neumann,   Dez 2005
#
array set opt {-reset 0 -change 1 -diff 0 -path . -name *tcl}
array set opt $argv

if {$opt(-reset)} {
  foreach file [exec find -L $opt(-path) -type f -name *-original] {
    regexp {^(.*)-original} $file _ new
    file delete $new
    file rename $file $new
  }
}
if {$opt(-diff)} {
    foreach file [exec find -L $opt(-path) -type f -name *-original] {
        regexp {^(.*)-original} $file _ new
        set status [catch {exec diff -wu $file $new} result]
        puts "---diff -wu $file $new"
        puts $result
    }
    exit
}

if {$opt(-change)} {
  set totalchanges 0
  set files 0
  foreach file [exec find -L $opt(-path) -type f -name $opt(-name)] {
      set F [open $file]; set c [read $F]; close $F
      set newFile ""
      set changes 0

      # make "Class create" explicit (add "create" to Class command)
      incr changes [regsub -all {(\n\s*)Class\s+([^acip])} $c {\1Class create \2} c]

      # [ad_quotehtml ...] -> [ns_quotehtml ...]
      incr changes [regsub -all {\[\s*ad_quotehtml } $c "\[ns_quotehtml " c]

      # [get_server_root] -> $::acs::rootdir
      incr changes [regsub -all {\[\s*[:]*cd(get_server_root|acs_root_dir)\s*\]} $c \
                        {$::acs::rootdir} c]


      # ![template::util::is_nil aa(bbb)] -> [info exists ...]
      incr changes [regsub -all {!\s*\[\s*template::util::is_nil\s+([a-zA-Z0-9_-]+\([a-zA-Z0-9_-]+\)|title)\s*\]} $c \
                        {[info exists \1]} c]

      # [template::util::is_nil aa(bbb)] -> ![info exists ...]
      incr changes [regsub -all {\[\s*template::util::is_nil\s+([a-zA-Z0-9_-]+\([a-zA-Z0-9_-]+\)|title)\s*\]} $c \
                        {![info exists \1]} c]

      # string is int -> string is integer
      incr changes [regsub -all {string\s+is\s+int\M} $c {string is integer} c]

      # [info command ...] -> [info commands ...]
      incr changes [regsub -all {\[\s*info\s+(command|proc)\s+(:?:?\$[a-zA-Z0-9_\(\):\{\}\$]+|\[[^\]]+\]|[:a-zA-Z0-9_.$*\"]+)\s*\]} $c \
                        {[info \1s \2]} c]

      # [file dir ...] -> [file dirname ...]
      incr changes [regsub -all {(\n\s*|\[)file\s+dir\s} $c {\1file dirname } c]
      # [file root ...] -> [file rootname ...]
      incr changes [regsub -all {(\n\s*|\[)file\s+root\s} $c {\1file rootname } c]

      # foreach ... break -> lassign
      incr changes [regsub -all {foreach\s+{([^\}]+)}\s+(\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+)\s+break(\s)} $c \
          {lassign \2 \1\3} c]
      incr changes [regsub -all {foreach\s+{([^\}]+)}\s+(\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+)\s+{\s*break\s*}(\s)} $c \
          {lassign \2 \1\3} c]

      # eval lappend array xxx -> lappend array {*}xxx
      incr changes [regsub -all {eval\s+lappend\s+(\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+|[0-9a-zA-Z_]+)\s+(\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+|[0-9a-zA-Z_]+)(\s|\})} $c \
                        {lappend \1 {*}\2\3} c]

      # eval append array xxx -> append array {*}xxx
      incr changes [regsub -all {eval\s+append\s+(\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+|[0-9a-zA-Z_]+)\s+(\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+|[0-9a-zA-Z_]+)(\s|\})} $c \
                        {append \1 {*}\2\3} c]


      # util_unlist ... break -> lassign
      incr changes [regsub -all {util_unlist\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[0-9a-zA-Z_]+)\s} $c \
          {lassign \1 } c]


      # [lindex $args [expr {$i + 1}]] -> [lindex $args $i+1]
      incr changes [regsub -all {\[\s*lindex\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+)\s*\}\s*\]\s*\]} $c \
                        {[lindex \1 \2\3\4]} c]

      # [lindex [lindex $args idx1] idx2] -> [lindex $args idx1 idx2]
      incr changes [regsub -all {\[\s*lindex\s+\[\s*lindex (\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+([0-9]+|[$\(\)a-z_A-Z0-9+-]+|\[[^\]]+\])\s*\]\s+([0-9]+|[$\(\)a-z_A-Z0-9+-]+|\[[^\]]+\])\s*\]} $c \
                        {[lindex \1 \2 \3]} c]



      # [string index $args [expr {$i + 1}]] -> [string index $args $i+1]
      incr changes [regsub -all {\[\s*string\s+index\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+)\s*\}\s*\]\s*\]} $c \
                        {[string index \1 \2\3\4]} c]

      # [lrange $list number [expr {$i + 1}]] -> [lrange $list number $i+1]
      incr changes [regsub -all {\[\s*lrange\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[0-9a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+|\[[^\]]+\])\s*\}\s*\]\s*\]} $c \
                        {[lrange \1 \2 \3\4\5]} c]

      # [lrange $list [expr {$i + 1}] $number] -> [lrange $list $i+1 $number]
      incr changes [regsub -all {\[\s*lrange\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+|\[[^\]]+\])\s*\}\s*\]\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[0-9a-zA-Z_]+)\s*\]} $c \
                        {[lrange \1 \2\3\4 \5]} c]

      # [string range $list number [expr {$i + 1}]] -> [string range $list number $i+1]
      incr changes [regsub -all {\[\s*string\s+range\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[0-9a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+|\[[^\]]+\])\s*\}\s*\]\s*\]} $c \
                        {[string range \1 \2 \3\4\5]} c]

      # [string range $list [expr {$i + 1}] $number] -> [string range $list $i+1 $number]
      incr changes [regsub -all {\[\s*string\s+range\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+|\[[^\]]+\])\s*\}\s*\]\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[0-9a-zA-Z_]+)\s*\]} $c \
                        {[string range \1 \2\3\4 \5]} c]

      # [string first $needle $hay [expr {$i + 1}]] -> [string first $needle $hay $args $i+1]
      incr changes [regsub -all {\[\s*string\s+first\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]+\")\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+\[\s*expr\s+\{\s*(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*([+-])\s*([0-9]+)\s*\}\s*\]\s*\]} $c \
                        {[string first \1 \2 \3\4\5]} c]


      #<property name="title">
      #incr changes [regsub -all {<property name="?title"?>} $c {<property name="doc(title)">} c]


      # acs_sc_call dotlrn_applet $op       $list_args      $applet_key
      #             contract      operation arguments(opt)  impl(opt)

      incr changes [regsub -all -- {\[\s*acs_sc_call\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s*\]} $c {[acs_sc::invoke -contract \1]} c]

      incr changes [regsub -all -- {\[\s*acs_sc_call\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s*\]} $c \
                        {[acs_sc::invoke -contract \1 -operation \2 -call_args \3 -impl \4]} c]

      incr changes [regsub -all -- {acs_sc_call\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)(\s*)} $c \
                        {acs_sc::invoke -contract \1 -operation \2 -call_args \3 -impl \4\5} c]

      incr changes [regsub -all -- {\[\s*acs_sc_call +-error +(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s+(\"[^\"]*\"|\[[^\[]+\]|[a-zA-Z0-9_()$]+)\s*\]} $c {[acs_sc::invoke -error -contract \1 -operation \2 -call_args \3 -impl \4]} c]


      # item::get_url [ -root_folder_id root_folder_id ] item_id ->
      #content::item::get_virtual_path -item_id item_id [ -root_folder_id root_folder_id ]

      incr changes [regsub -all {\[\s*item::get_url\s+-root_folder_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+([^\s]+)\s*\]} $c \
                        {[content::item::get_virtual_path -root_folder_id \1 -item_id \2]} c]

      # cr::keyword::item_assign -item_id item_id -keyword_id keyword_id [ -singular ]
      # -> content::keyword::item_assign -item_id item_id -keyword_id keyword_id \
          # [ -context_id context_id ] [ -creation_user creation_user ] \
          # [ -creation_ip creation_ip ]

      incr changes [regsub -all {cr::keyword::item_assign\s+-item_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+-keyword_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)} $c \
                        {content::keyword::item_assign -item_id \1 -keyword_id \2} c]
      incr changes [regsub -all {cr::keyword::item_assign\s+-singular\s+-item_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+-keyword_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)} $c \
                        {content::keyword::item_assign -item_id \1 -keyword_id \2} c]


    # [ad_get_user_id]
      incr changes [regsub -all {\[\s*ad_get_user_id\s*\]} $c {[ad_conn user_id]} c]
      # [ad_verify_and_get_user_id]
      incr changes [regsub -all {\[\s*ad_verify_and_get_user_id\s*\]} $c {[ad_conn user_id]} c]

      # [ad_maybe_redirect_for_registration]
      incr changes [regsub -all {([^ ])ad_maybe_redirect_for_registration} $c {\1auth::require_login} c]


      # [util_quote_double_quotes] -> [ad_quotehtml]
      incr changes [regsub -all {\[\s*util_quote_double_quotes\s+} $c {[ad_quotehtml } c]

      # template::util::quote_html -> [ad_quotehtml]
      incr changes [regsub -all {\[\s*template::util::quote_html\s+} $c {[ad_quotehtml } c]

      # philg_quote_double_quotes -> [ad_quotehtml]
      incr changes [regsub -all {\[\s*philg_quote_double_quotes\s+} $c {[ad_quotehtml } c]

      # util_convert_plaintext_to_html -> ad_text_to_html
      incr changes [regsub -all {\[\s*util_convert_plaintext_to_html\s+} $c {[ad_text_to_html } c]

      # [export_form_vars ...] -> [export_vars ...]
      incr changes [regsub -all {\[\s*export_form_vars\s+-sign\s+([^\]=]+)\s*\]} $c {[export_vars -form -sign {\1}]} c]
      incr changes [regsub -all {\[\s*export_form_vars\s+([^\]=]+)\s*\]} $c {[export_vars -form {\1}]} c]
      # [ad_export_vars ...] -> [export_vars ...]
      incr changes [regsub -all {\[\s*ad_export_vars\s+} $c {[export_vars } c]

      # [export_url_vars ...] -> [export_vars ...]
      incr changes [regsub -all {\[\s*(export_url_vars\s+[^\]]+)\s+([a-zA-Z_]+)=([a-zA-Z_\$]+)(\s*[^\]]*)\]} $c \
                      {[\1 {\2 \3}\4]} c]
      incr changes [regsub -all {\[\s*(export_url_vars\s+[^\]]+)\s+([a-zA-Z_]+)=([a-zA-Z_\$]+)(\s*[^\]]*)\]} $c \
                      {[\1 {\2 \3}\4]} c]
      incr changes [regsub -all {\[\s*(export_url_vars\s+[^\]]+)\s+([a-zA-Z_]+)=([a-zA-Z_\$]+)(\s*[^\]]*)\]} $c \
                      {[\1 {\2 \3}\4]} c]
      incr changes [regsub -all {\[\s*export_url_vars\s+([^\]=]+)\]} $c {[export_vars -url {\1}]} c]


      # set mount_url "mount?[export_vars -url {expand:multiple root_id node_id}]"
      incr changes [regsub -all {"([a-zA-Z0-9_./$-]+)[?]\[export_vars +-url +([^\]\[]+)\]"} $c \
                        {[export_vars -base \1 \2]} c]
      incr changes [regsub -all {"([a-zA-Z0-9_./$-]+)[?]\[export_vars +([^\]\[]+)\]"} $c \
                        {[export_vars -base \1 \2]} c]
      incr changes [regsub -all {list +([a-zA-Z0-9_./$-]+)[?]\[export_vars +([^\]\[]+)\]} $c \
                        {[export_vars -base \1 \2]} c]
      incr changes [regsub -all {"(\[ad_conn url\])[?]\[export_vars +([^\]\[]+)\]"} $c \
                        {[export_vars -base \1 \2]} c]
      incr changes [regsub -all {\[export_vars\s+-url\s+([^\]\[]+)\]} $c \
                      {[export_vars \1]} c]

      incr changes [regsub -all {([a-zA-Z0-9_$-]+)[?]\[export_vars +} $c \
                        "\[export_vars -base \\1 " c]



      # [site_node_closest_ancestor_package key] -> [site_node::closest_ancestor_package -package_key package_key]
      incr changes [regsub -all {\[\s*site_node_closest_ancestor_package\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[^\s]+)\s*\]} $c \
                        {[site_node::closest_ancestor_package -include_self -package_key \1]} c]
      #	[site_node_closest_ancestor_package -url $url dotlrn]
      incr changes [regsub -all {\[\s*site_node_closest_ancestor_package\s+-url\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[^\s]+)\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[^\s]+)\s*\]} $c \
                        {[site_node::closest_ancestor_package -include_self -url \1 -package_key \2]} c]


      # [site_node_closest_ancestor_package -default [ad_conn package_id] dotlrn]

      # [site_node_closest_ancestor_package_url] [lindex [site_node::get_url_from_object_id ...] 0]
      incr changes [regsub -all {\[\s*site_node_closest_ancestor_package_url\s*\]} $c \
                        {[lindex [site_node::get_url_from_object_id -object_id [site_node::closest_ancestor_package -include_self -package_key [subsite::package_keys]]] 0]} c]
      incr changes [regsub -all {\[\s*site_node_closest_ancestor_package_url\s+-package_key\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[^\s]+)\s*\]} $c \
                        {[lindex [site_node::get_url_from_object_id -object_id [site_node::closest_ancestor_package -include_self -package_key \1]] 0]} c]

      # ad_permission $var spaceless-token
      incr changes [regsub -all {\[\s*ad_permission_p (\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+) +([^\s]+)\s*\]} $c \
                        {[permission::permission_p -object_id \1 -privilege \2]} c]
      incr changes [regsub -all {\[\s*ad_permission_p -user_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+) +([^\s]+)\s*\]} $c \
                        {[permission::permission_p -party_id \1 -object_id \2 -privilege \3]} c]

      # [ad_parameter /param/ /pkg/ /default] ->
      # ad_parameter spaceless-token spaceless-token [parameter::get -parameter \1 -default \3]
      #... [ad_parameter SolicitCommentsP "news" 0] .... ignored package key
     incr changes [regsub -all {\[\s*ad_parameter\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[^\s]+|\"[^\"]*\")\s+([^\s]+)\s*\]} $c \
                        {[parameter::get -parameter \1 -default \3]} c]

     # ad_parameter "show_portrait_p" dotlrn
     incr changes [regsub -all {\[\s*ad_parameter\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")\s+([^\s]+)\s*\]} $c \
                        {[parameter::get -parameter \1]} c]

     # ad_parameter -localize subcommunities_pretty_name dotlrn
     incr changes [regsub -all {\[\s*ad_parameter\s+-localize\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")\s+([^\s]+)\s*\]} $c \
                        {[parameter::get -localize -parameter \1]} c]

      incr changes [regsub -all {\[\s*ad_parameter\s+-package_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\"[^\"]*\")\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")\s+([^\s]+|\"[^\"]*\")\s*\]} $c \
                        {[parameter::get -package_id \1 -parameter \2 -default \3]} c]

      incr changes [regsub -all {\[\s*ad_parameter\s+-package_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\"[^\"]*\")\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")\s+([^\s]+)\s*\]} $c \
                        {[parameter::get -package_id \1 -parameter \2 -default \3]} c]

      incr changes [regsub -all {\[\s*ad_parameter\s+-package_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\"[^\"]*\")\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")\s+([^\s]+)\s+([^\s]+|\"[^\"]*\")\s*\]} $c \
                        {[parameter::get -package_id \1 -parameter \2 -default \4]} c]

      # ad_parameter "StoreFilesInDatabaseP" -package_id [ad_conn package_id]
      incr changes [regsub -all {\[\s*ad_parameter\s+-package_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\[[^\]]+\]|)\s+([^\s]+|\"[^\"]*\")\s*\]} $c \
                        {[parameter::get -package_id \1 -parameter \2]} c]
      incr changes [regsub -all {\[\s*ad_parameter\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[^\s]+)\s*\]} $c \
                        {[parameter::get -parameter \1]} c]

      #  ad_parameter -package_id $package_id -set 1 community_level_p
      incr changes [regsub -all {ad_parameter\s+-package_id\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\"[^\"]*\")\s+-set\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\"|[0-9a-z_]+)\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+|\"[^\"]*\")} $c \
                        {parameter::set_value -package_id \1 -parameter \3 -value \2} c]




      # ad_require_permission spaceless-token spaceless-token
      incr changes [regsub -all {ad_require_permission\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s+([^\s]+) *\n} $c \
                        {permission::require_permission -object_id \1 -privilege \2
} c]

      # item::get_live_revision $var
      incr changes [regsub -all {\[\s*item::get_live_revision\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|[a-zA-Z_]+)\s*\]} $c \
                        {[content::item::get_live_revision -item_id \1]} c]


      if {1} {
      # general "lsearch (-exact|-glob|-regexp|sorted) list pattern"
      # > -1, != -1

          # [lsearch {name widget datatype} $var] < 0 ...
          incr changes [regsub -all {if\s+[\{]\s*[\[]lsearch\s+([\{]\s*[^\}]+[\}])\s+(\$[a-zA-Z0-9_]+)\s*[\]]\s+(<\s*0|==\s*-1)\s*[\}]} $c \
                            {if {\2 ni \1}} c]
          incr changes [regsub -all {if\s+[\{]\s*[\[]lsearch\s+([\{]\s*[^\}]+[\}])\s+(\$[a-zA-Z0-9_]+)\s*[\]]\s+(>\s*-1)\s*[\}]} $c \
                            {if {\2 in \1}} c]

      # lsearch $var "pattern-without-*"
      incr changes [regsub -all {if +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +("[^\"\*]*"|\$[a-zA-Z0-9]_id) *\] *(>|!=) *-1 *\}} $c \
                    {if {\2 in \1}} c]
      # lsearch -exact $var "quoted-string"
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\[\[[^\]]+\][^\]]+\]|\{[^\}]+\}) +("[^\"]*"|\$[a-zA-Z0-9._\(\)]+) *\] *(>|!=) *-1 *\}} $c \
                    {\1 {\3 in \2}} c]

      # lsearch $var unquoted string without *
      incr changes [regsub -all {if +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^* ]*) *\] *(>|!=) *-1 *\}} $c \
                    {if {"\2" in \1}} c]
      # lsearch -exact $var unquoted-string
      incr changes [regsub -all {if +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^ ]*) *\] *(>|!=) *-1 *\}} $c \
                    {if {"\2" in \1}} c]
      # lsearch -exact $var [...]
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +-(exact|integer)\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+) *\] *(>|!=) *-1 *\}} $c \
                    {\1 {\4 in \3}} c]

      # lsearch -exact $var [...]
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +-(exact|integer)\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\$[a-zA-Z0-9_\(\):\$]+) *\] *(==) *-1 *\}} $c \
                    {\1 {\4 ni \3}} c]

    # >= 0

      # lsearch $var "pattern-without-*"
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +("[^\"\*]*"|\$[a-zA-Z0-9]_id) *\] *>= *0 *\}} $c \
                    {\1 {\3 in \2}} c]
      # lsearch -exact $var "quoted-string"
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\{[^\}]+\}) +("[^\"]*"|\$[a-zA-Z0-9_]+|\[[^\]]+\]) *\] *>= *0 *\}} $c \
                    {\1 {\3 in \2}} c]

      # lsearch $var unquoted string without *

      incr changes [regsub -all {if +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^* ]*) *\] *>= *0 *\}} $c \
                    {if {"\2" in \1}} c]
      # lsearch -exact $var unquoted-string
      incr changes [regsub -all {if +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^ ]*) *\] *>= *0 *\}} $c \
                    {if {"\2" in \1}} c]


    # == -1

      # lsearch $var "pattern-without-*"
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\{[^\}]+\}) +("[^\"\*]*"|\$[a-zA-Z0-9]_id) *\] *== *-1 *\}} $c \
                    {\1 {\3 ni \2}} c]
      # lsearch -exact $var "quoted-string"
      incr changes [regsub -all {(if|expr) +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]|\{[^\}]+\}) +("[^\"]*"|\$[a-zA-Z0-9_]+) *\] *== *-1 *\}} $c \
                    {\1 {\3 ni \2}} c]

      # lsearch $var unquoted string without *

      incr changes [regsub -all {if +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^* ]*) *\] *== *-1 *\}} $c \
                    {if {"\2" ni \1}} c]
      # lsearch -exact $var unquoted-string
      incr changes [regsub -all {if +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^ ]*) *\] *== *-1 *\}} $c \
                    {if {"\2" ni \1}} c]

      # lsearch -exact $var $var
      incr changes [regsub -all {if +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) *\] *== *-1 *\}} $c \
                    {if {"\2" ni \1}} c]


    # < 0

      # lsearch $var "pattern-without-*"
      incr changes [regsub -all {if +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +("[^\"\*]*"|\$[a-zA-Z0-9]_id) *\] *< *0 *\}} $c \
                    {if {\2 ni \1}} c]
      # lsearch -exact $var "quoted-string"
      incr changes [regsub -all {if +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +("[^\"]*"|\$[a-zA-Z0-9_\(\)]+) *\] *< *0 *\}} $c \
                    {if {\2 ni \1}} c]

      # lsearch $var unquoted string without *

      incr changes [regsub -all {if +\{ *\[lsearch +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^* ]*) *\] *< *0 *\}} $c \
                    {if {"\2" ni \1}} c]
      # lsearch -exact $var unquoted-string
      incr changes [regsub -all {if +\{ *\[lsearch +-exact +(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\]) +([a-zA-Z:0-9_][^ ]*) *\] *< *0 *\}} $c \
                    {if {"\2" ni \1}} c]


      # [llength [array names ...]] -> [array size ...]
      incr changes [regsub -all {\[llength\s+\[array names\s+([a-zA-Z0-9_]+)\s*\]\s*\]} $c \
                        {[array size \1]} c]

      # cr::keyword::new -> content::keyword::new
      # cr::keyword::new -heading $name_2 -parent_id $new_keyword_id
      incr changes [regsub -all {\[\s*cr::keyword::new } $c {[content::keyword::new } c]

      # cc_email_from_party -> party::email -party_id
      incr changes [regsub -all {\[\s*cc_email_from_party } $c {[party::email -party_id } c]

      # cc_email_user -> party::get_by_email -email
      # cc_lookup_email_user -> party::get_by_email -email
      incr changes [regsub -all {\[\s*cc_email_user } $c {[party::get_by_email -email } c]
      incr changes [regsub -all {\[\s*cc_lookup_email_user } $c {[party::get_by_email -email } c]

      # cc_screen_name_user -> acs_user::get_user_id_by_screen_name -screen_name
      # cc_lookup_screen_name_user -> acs_user::get_user_id_by_screen_name -screen_name
      incr changes [regsub -all {\[\s*cc_screen_name_user} $c \
                        {[acs_user::get_user_id_by_screen_name -screen_name } c]
      incr changes [regsub -all {\[\s*cc_lookup_screen_name_user } $c \
                        {[acs_user::get_user_id_by_screen_name -screen_name } c]

      incr changes [regsub -all {\[get_server_root\]} $c {[acs_root_dir]} c]

      #cc_lookup_name_group -> group::get_id
      # cc_name_to_group -> group::get_id

      incr changes [regsub -all {\[\s*cc_lookup_name_group } $c \
                        {[group::get_id -group_name } c]
      incr changes [regsub -all {\[\s*cc_name_to_group } $c \
                        {[group::get_id -group_name } c]

    # deprecated: dt_format -format format -gmt gmt time
    # -> lc_time_fmt datetime fmt [ locale ]

    # deprecated: ns_tmpnam -> ad_tmpnam
    incr changes [regsub -all {\[\s*ns_tmpnam\s*\]} $c {[ad_tmpnam]} c]

    # deprecated: site_node_id -> site_node::get_node_id -url
    incr changes [regsub -all {\[\s*site_node_id\s*(\S)} $c {[site_node::get_node_id -url \1} c]


    # deprecated ad_permission_grant user_id object_id privilege
    # permission::grant -party_id party_id -object_id object_id -privilege privilege

      incr changes [regsub -all {ad_permission_grant\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+([a-zA-Z:0-9_][^ ]*)} $c \
                        {permission::grant -party_id \1 -object_id \2 -privilege \3} c]

      incr changes [regsub -all {ad_permission_revoke\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+(\$[a-zA-Z0-9_\(\):\$]+|\[[^\]]+\])\s+([a-zA-Z:0-9_][^ ]*)} $c \
                        {permission::revoke -party_id \1 -object_id \2 -privilege \3} c]


      # " @version $Id" -> " @cvs-id $Id"
#     incr changes [regsub -all { @version \$Id} $c { @cvs-id $Id} c]

      # " @cvs_id $Id" -> " @cvs-id $Id"
#      incr changes [regsub -all { @cvs_id \$Id} $c { @cvs-id $Id} c]

      # " @creation_date 2" -> " @creation-date 2"
      #incr changes [regsub -all { @creation_date 2} $c { @creation-date 2} c]

      incr changes [regsub -all {tDOM::xmlReadFile} $c {tdom::xmlReadFile} c]

  }


   if {$changes > 0} {
     puts "... updating $file ($changes changes)"
     set F [open /tmp/XXX w]; puts -nonewline $F $c; close $F
     file rename $file $file-original
     set F [open $file w]; puts -nonewline $F $c; close $F
     incr totalchanges $changes
     incr files
  }
  }
  puts "$totalchanges changes in $files files"
}
