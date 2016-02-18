# Iptables_Semantics

A formal semantics of the Linux netfilter iptables firewall.
Written in the [Isabelle](https://isabelle.in.tum.de/) interactive proof assistant.

It features
  * A real-world model of IPv4 addresses as 32bit machine words
  * Executable code
  * Support for all common actions in the iptables filter table: ACCEPT, DROP, REJECT, LOG, calling to user-defined chains, RETURN, GOTO to terminal chains, the empty action
  * Support for ALL primitive match conditions (by abstracting over unknown match conditions)
  * Translation to a simplified firewall model
  * Certification of spoofing protection 
  * ...


![isabelle/hol logo](https://raw.githubusercontent.com/diekmann/Iptables_Semantics/refactoring/images/isabelle.png "Isabelle/HOL")


### Obtaining

Checkout:
This repository depends on the [seL4](https://github.com/seL4/l4v/) libraries (for the bitmagic operations on IPv4 addresses).
After cloning this repository, you need to initialized this submodule.
```
$ git submodule init
$ git submodule update
$ #now patch l4v for Isabelle2016
```

Apply the patch in thy/Bitmagic/l4v.patch. It is only three lines. seL4 is not yet ported for Isabelle2016.


### Isabelle Theory files
---

Checking all proofs:

```
$ isabelle build -v -d . -o document=pdf Iptables_Semantics_Examples2
```
This needs some hours on my laptop.


Building the documentation:

```
$ isabelle build -d . -v -o document=pdf Iptables_Semantics_Documentation
```
The build takes less than 10 minutes on my laptop (14min CPU time, 2 threads).
The documentation summarizes the most important definitions and theorems.
It is deliberately very very brief and only provides results.
It should contain the summarizing correctness theorems for all executable functions we export.
This is probably the best point to get started working with the theory files.


To develop, we suggest to load the Bitmagic theory as heap-image:
```
$ isabelle jedit -d . -l Bitmagic
```

Check the Examples directory to get started

### Haskell Tool

| Component             | Status |
| --------------------- | ------ |
| Haskell tool          | [![Build Status](https://travis-ci.org/diekmann/Iptables_Semantics.svg)](https://travis-ci.org/diekmann/Iptables_Semantics) |

See README.md in haskell_tool.


### Talks
  * 32C3: Verified Firewall Ruleset Verification, Cornelius Diekmann, Hamburg, Germany, December 2015 [[description]](https://events.ccc.de/congress/2015/Fahrplan/events/7195.html) [[video]](https://media.ccc.de/v/32c3-7195-verified_firewall_ruleset_verification#video)

### Academic Publications

  * Cornelius Diekmann, Lukas Schwaighofer, and Georg Carle. Certifying spoofing-protection of firewalls. In 11th International Conference on Network and Service Management, CNSM, Barcelona, Spain, November 2015. [[preprint]](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/diekmann2015_cnsm.pdf)
  * Cornelius Diekmann, Lars Hupel, and Georg Carle. Semantics-Preserving Simplification of Real-World Firewall Rule Sets. In 20th International Symposium on Formal Methods, June 2015. [[preprint]](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/fm15_Semantics-Preserving_Simplification_of_Real-World_Firewall_Rule_Sets.pdf), [[springer | paywall]](http://link.springer.com/chapter/10.1007%2F978-3-319-19249-9_13)

The raw data of the iptables rulesets from the Examples is stored in [this](https://github.com/diekmann/net-network) repositoy.


### Contributors
   * [Cornelius Diekmann](http://www.net.in.tum.de/~diekmann/)
   * [Lars Hupel](http://lars.hupel.info/)
   * [Julius Michaelis](http://liftm.de)
   * Max Haslbeck
   * Stephan-A. Posselt
   * Lars Noschinski





