# Conditional Compilation of Features in RAGE1

This documet is intended as an internal reference for RAGE1 development, not
as a general document on conditional compilation.  A knowledge of the basics
of C macro definitions is asumed; this document describes the infrastructure
for conditional compiling in RAGE1 source code.

## General mechanism

The conditional compilation snippets in RAGE1 are in common use elsewhere:
the code to be conditionally compiled is enclosed between two preprocessor
directives:

~~~
#ifdef BUILD_FEATURE_MY_OPTIONAL_FEATURE
    void run_optional_feature( void ) {
        (...do something...)
    }
#endif
~~~

In the above code, if the C macro `BUILD_FEATURE_MY_OPTIONAL_FEATURE` is
defined at compile time, the code will be compiled, and otherwise it won't,
and will not be included in the main binary.

The DATAGEN tool has been modified to generate a new `features.h` file, with
all the macro definitions for the features that are used in the game data. 
Also, all RAGE1 header files have been also modified to include the
`features.h` file before any other RAGE1 include, so that conditional
compilation macros are available early during the compilation process.

All code that is to be conditionally compiled (either in RAGE1 or in your
game) must inclufe the `features.h` file as the first non-system include
file, for those same reasons.

## Conditional Compilation of Flow checks and rules

The first uses of the conditional compilation infrastructure have been the
Flow rule checks and actions: there are more than two dozens checks and
actions available, but not all of them will be used on all games. Since each
action and check uses a specific function, it makes no sense to have all the
flow possibilities in every RAGE1 game: only the ones used in the game
should be compiled in.

Thus, all Flow rule checks and actions and its related data (check and
action tables) have been setup with feature macros as defined above to
achieve that result. The `flow.c` source code under `engine/src` can be
reviewed for details.

In case of adding a new conditionally compiled check or action, the
following rules must be followed:

- The name of the check/action must include only letters, numbers and '_'
  character

- The function check/action name in `flow.c` must be named
  `do_rule_check_<my_new_check>` or `do_rule_action_<my_new_action>`
  (replace the "my_new_..." text with your check name

- The name of the check in GDATA files and the function name must match:
  i.e. for the `MY_NEW_CHECK` check, the function must be named
  `do_rule_check_my_new_check`

- Following the mentioned rules, the DATAGEN tool will automatically
  generate the conditional compilation macro for the mentioned new check
  with the following format: `BUILD_FEATURE_FLOW_RULE_CHECK_MY_NEW_CHECK`

- You can use then this macro name to be defined in the source for compiling
  the affected function or not.
