# Correctness And Consistency Decisions

As we mentioned in the README, fsynth is a helper to batch simple file
operations. Not only it does not have the goal of being a reliable fs tool, but
it actively dis encourages you to see it that way. 

You may assume that if, between doing the synthetic operation and the actual
execution results will be unpredictable and likely wrong. Doing otherwise would
require a wall and other things, which are not this projects goal
not scope. 

That said, we're taking care not to do stupid things, not to delete data unless
requested to do so, and generally work in a safe and predictable manner.

This document explains some of the design decisions and implications as a way
to help you make a more informed decision.


## Tansactions , Undo and Tolerance Mode

There are scenarios in which a state can be the things you requested, but that
might be caused by bad behavior elsewhere.  For example, you issue an undo.
One of the operations created a directory, and now, when undoing , will delete
it.  When about to run, the operation see that this directory is no longer
there, it has already been deleted.

This is the dilema: the directory's deletion is what you, the user, requested
and expected. However, it was not deleted by the undo process, and we don't
know what that could be.

In such scenarios, we could go a strict route, raising an error. In the
other hand, if the desired outcome is what was requested, we can be tolerant for
the how, and satisfy ourselves with the outcome matching your expectation.

This is the tolerance mode, and it's a assumption spread out at various levels
during  undos.  We consider the state outcome not to warrant a halt and failure
of further steps.
