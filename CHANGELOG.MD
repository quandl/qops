# 1.4.9
* fix issue where status 0 is return on certain errors

# 1.4.8
* fixed empty online instances check

# 0.9.2

* Added options to select migrate database, but default migrate option is true.

# 0.9.0

* Added the clean command to be used to clean old staging instances that have not had commands run against them for a given period.

# 0.7.0

* Refactored options to use thor class options for environment and branches
* Refactored pre-task run step to fail more gracefully
* Fix issue with help not displaying by using un-released thor version
* Fix issue with migration being run on all servers for production deployments
* Handle case where git does not exist on users system 

# <= 0.6.3

* Initial release
