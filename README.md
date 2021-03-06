JAMES (JUnit Model Extractor) [![Build Status](https://travis-ci.org/palas/james.svg?branch=master)](https://travis-ci.org/palas/james) [<img src="http://quickcheck-ci.com/p/palas/james.png" alt="Build Status" width="160px">](http://quickcheck-ci.com/p/palas/james)
=============================

JAMES is a tool that aims at generating new tests for Web Services from existing JUnit tests. Currently it extracts a model in `.dot` format which can be rendered with the tool `dot` from Graphviz.

JAMES tool consists of two parts, a dynamic library (written in C++), and a server (written in Erlang). Both parts are designed to work in parallel. The dynamic library uses the JVMTI API to instrument the execution of JUnit Java tests and sends filtered trace information to the Erlang server. The Erlang server applies more complex filters and algorithms in order to generate the models.

## Compilation

Both parts of JAMES tool must be compiled independently.

### JVMTI Agent (Dynamic Library)

The source for the JVMTI Agent is located at the folder `agent`. It includes compilation scripts generated by autotools. They can be run by executing the following sequence of commands:

```bash
./autogen.sh
./configure
make
```

This should generate a file called libjames.so in a subdirectory called `.libs`. Note that the source of the agent depends on:

* __Boost libraries__ - Usually available as a dev package: libboost-dev
* __Java JRE__ - The same that is used for running the tests should be used. The `configure` script tries to locate the Java directory by itself by searching the path in which the program `javac` is located. In case that does not work, it will look for the environment variable `$JAVA_HOME`.

### Erlang Server

Source for the Erlang server is located in the folder `server`. It does not include any compilation scripts, but it can be easily compiled by executing:

```bash
erl -make
```

from the same folder. Or more conveniently:

```erl
make:all([load]).
```

from the Erlang interpreter.

## Usage

To extract a diagram from a set of JUnit tests, you must first initialise the Erlang Server, then run the JUnit tests using the JVMTI Agent, and then parse the traces that are stored in the server.

### JVMTI Agent (Dynamic Library)

The JVMTI Agent may be deployed by adding a parameter to the call to the Java JVM:

```bash
java -agentpath:/home/tux/Desktop/james/agent/.libs/libjames.so=4321
```
where 4321 is the port in which the Erlang Server is listening. Alternatively, it can be added to the environment variable `_JAVA_OPTIONS`, which is very convenient when the JUnit tests are being executed through a build automation tool like `ant` or `maven`:

```bash
export _JAVA_OPTIONS="-agentpath:/home/tux/Desktop/james/agent/.libs/libjames.so=4321"
```

### Erlang Server

The server itself can be controlled by the module `server`, which is implemented as a `gen_server`. Some of the commands it provides are:

* __`server:start()`__ - it starts the server and starts listening. It returns a tuple in the form `{ok, Pid, Port}` where Port is the port that the server is listening to, and Pid is the process identifier that the other commands require.

* __`server:stop(Pid)`__ - it stops the server and frees all the information stored.

* __`server:save_messages(Pid, FileNameAndPath)`__ - saves all the complete traces that are stored in the server to the file specified.

* __`server:load_messages(Pid, FileNameAndPath)`__ - loads information stored by `save_messages/2`.

* __`server:clear_messages(Pid)`__ - removes the information stored in the server, it may cause errors if JVMTI agents are still running.

Diagrams can be generated by using the module `parser_newstruct`, some available commands are:

* __`parser_newstruct:list_traces(Pid)`__ - fetches all the sets of traces in the server and returns a list of tuples in the form `{TracePos, TraceLength}`, where `TracePos` is the identifier and `TraceLength` is the length of a trace. Identifiers for each trace set are temporary and may change if new agents sent new traces to the server.
* __`parser_newstruct:gen_dia_to_files(Pid, TracePos, FilePathAndPrefix)`__ - generates a diagram for the specified set of traces and writes it in `.dot` format in files that start by `FilePathAndPrefix` and end with a number and the extension `.dot`.
* __`parser_newstruct:gen_dia_to_files(Pid, TracePos, FilePathAndPrefix, Config)`__ - it does the same than the three parameter version but allows the user to include a `#config{}` record with the fields described below. The three parameter version uses the default version of the record as defined in the header file: `records.hrl`


`#config{}` record has currently the following fields:

* __`remove_bubbles`__ - expects a boolean that specifies whether elliptic nodes should be removed from the diagram.
* __`highlight_loops`__ - specifies whether transitions that form a loop should be highlighted.
* __`collapse_integers`__ - when `true` alternative integers that form a sequence are joined in a node titled `integer_range`.
* __`collapse_strings`__ - when `true` it merges several consecutive invocations of `append` applied to constants into a single one.
* __`single_file`__ - specifies whether all the islands in the diagram should be included in the same file.
* __`num_of_islands`__ - sets a maximum limit for the num of islands that are included, if the number of island exceeds this limit, only the ones with a higher number of nodes are included. If the atom `inf` is provided, all the islands will be included.
* __`big_k_value`__ - value used for `K` in the K-tails-like algorithm used.
* __`small_k_value`__ - value used for `K` when trying to merge sequences that have the same root. It does not have effect if it is bigger than the `big_k_value`.
* __`remove_orphan_nodes`__ - specifies whether islands of a single node should be included in the diagram.
* __`discard_calls_beginning_with`__ - expects a list of strings, and any call to a method starting with one of the strings provided will be ignored by the algorithm, (as it had never happened). It may provoke unidentified objects.
* __`remove_nodes_up_from`__ - expects a list of strings, any node whose label matches a string in the list will be removed, and all of its dependencies will be removed too, (independently of whether they are dependencies of other nodes or not).

## Understanding the results

While running the target test suite, James tracks every call that is executed within the Java Virtual Machine.
Those calls that do not belong to one of the filtered packages are checked for JUnit annotations.
In case a method has the JUnit annotations `@Before`, `@After`, or `@Test`, the calls that are executed within that method
will be shown in the diagram, together with all the dependencies for these calls that can be traced back to previous
method calls.

After all the traces have been stored, the second step puts them into a graph and looks for similar patterns to collapse
so that it the graph is more general and easier to read.

The algorithm is inspired by K-Tails [\[1\]](#biermann), 
it mainly tries to merge subtrees that have depth big-k, as specified in the configuration, and pairs
of subtrees that have at least depth small-k, but that end in the borders of the graph (leaf and root nodes).

This graph is then rendered into a diagram. Most of the information in the diagram is encoded in the shapes,
the colours and the borders of its elements, which we cover next.

### Nodes

Nodes can be classified according to their shape:
- Rectangular nodes represent calls to methods.
- Elliptical nodes represent values of Java's primitive types, (e.g: `int`, `char`, `bool`), as opposed to, for example: `Integer`, `Character`, `Boolean`
  * An exception to this are the "unidentified objects", which are objects that are first found by the system outside
    of the call to the constructor that originally created them. These kind of objects are represented by a tuple labeled `obj`.
  * Another exception is the case of `String`s and `StringBuffers`, which are interpreted as a fake primitive type called `string`, even
    though they are in fact normal objects. But because they are easily serialisable, we thought it was better this way.
- Diamond nodes, (`one_of` nodes), are just a way of grouping arrows that we will explain later.

We can also classify nodes according to the colour of their border:
- If the call belongs to a method labelled `@Test`, its border will be blue.
- If the call belongs to a method labelled `@Before`, its border will be green.
- If the call belongs to a method labelled `@After`, its border will be red.
- If the node is the result of merging nodes of calls that belong to methods with different annotations, its colour will be the result
of the "colour addition". For example, in case a node represents both a call in a method with annotation `@Test`, and a method with
annotation `@After`, its colour will be purple.
  There are two exceptions to this:
  * In case all of the three colours are mixed, the result will be black instead of white.
  * In case no colours are mixed, (the method was only included because of a dependency), the colour will be grey instead of black.

In the case of rectangular nodes, we can see that some nodes also have a double outline. This indicates that the call represented by
the node is static.


### Arrows

Arrows represent dependencies among nodes. The main distinction among arrows is colour:
- If an arrow is grey (or red), it represents a data dependency
- If an arrow is brown, it represents a control dependency

#### Data dependencies

Data dependencies represent that the return value of a call to a method (the origin of the arrow), is used as a parameter by another
call to a method (the one pointed to by the arrow) or, in case of dashed-arrows, as the target object of the call to a method (the `this` of the object).

Each method node, (i.e: elliptic node), receives as many data dependency arrows, (i.e: grey or red arrows), as parameters. In addition,
if the method is dynamic, it will receive an extra dashed arrow. If the method is static, it will have double outline instead.

When merging several nodes, the dependencies may be different. To keep the property stated in the previous paragraph, we use the `one_of` nodes to
group arrows before connecting them to a node. Between a `one_of`, and the destination node, there will be only one arrow. So we may have as many
`one_of`'s as parameters the destination method has, (plus one in the case of dynamic methods).

Wide arrows highlight the presence of loops, either in data dependencies, in control dependencies, or in a combination of both.
This effect can be disabled in the configuration record for clarity.

The origins of the dependency arrows, (around their origin nodes), are conditioned by the order in which the methods, (represented by the nodes at their ends),
were executed. James does this by using a couple of heuristics. If heuristics conflict, the arrows affected will be coloured red instead of gray.
But even when arrows are gray, the order of their origins may differ from the order of execution of the methods represented by the nodes at their ends.

#### Control dependencies

Methods that make HTTP requests (identified by a call to `openConnection` of the class `java.net.URLConnection`) are tagged, and they are linked with brown arrows in the order in which they are executed, and these links are kept through the merging process.

This HTTP requests are also classified in clusters or subgraphs, together with all the nodes that depend on them and that cannot be tracked as belonging to another HTTP request. HTTP requests are grouped by URL and HTTP method, (e.g: GET, POST, PUT...)

They are also assigned different classes depending on the nodes that depend on them, (inside the cluster):
 - if the nodes that depend on them contain the string `error` or `fail`, they are assigned the class `error`
 - if they belong to a method with the annotation `@After`, they are assigned to the class `tearDown`
 - otherwise they are assigned to the class `normal`

HTTP nodes that belong to different classes will never be merged.

#### Extra considerations

There are some limitations to the principles described before, that must be taken into account when interpreting
the diagrams produced by James.

- Operators like `!`, or `&&` are not tracked. They could be tracked in the future by using dynamic bytecode modification.
- Some methods are not tracked. This may happen with methods which are implemented natively, or that are generated in runtime.
Some of the information required is not always provided by JVMTI API for some of these methods.

This causes information to be lost,
  in particular, the tracking of values with primitive types is lost.
  For example:
  - If the result of a method is the `bool` value `false`, and we apply the operator `!`, the system will not
    be able to realise that the new `true` value is related to the old `false`, and it will consider that the
    new `true` value is hard-coded, which breaks the natural dependency sequence.
    * This problem could possibly be solved in the future with the use of more careful tracking techniques.
  - Another problem, (very related to the previous), is that primitive values cannot be tracked, (unlike objects).
    We use an heuristic that assumes that if a value of "primitive type" is used twice, a dependency is created
    from its last usage.
    * This may create fake dependencies in cases where the same primitive value is returned by different methods,
      before it is used as a parameter for a third one.
  - Finally, there is also a problem with the tracking of arrays and their contents. They are always identified
    by the system as "unidentified objects" since they are not implemented yet by James.

<a name="biermann" />[1] &nbsp; **Biermann, Alan W and Feldman, Jerome A.**
_On the synthesis of finite-state machines from samples of their behavior._
IEEE. p. 592--597 1972

