# FRBNY DSGE Model (Version 990.2)
[![Build Status](https://travis-ci.org/FRBNY-DSGE/DSGE.jl.svg)](https://travis-ci.org/FRBNY-DSGE/DSGE.jl)

The *DSGE.jl* package implements the FRBNY DSGE model and provides general code
to estimate many user-specified DSGE models. The package is introduced in the
Liberty Street Economics blog post
[The FRBNY DSGE Model Meets Julia](http://libertystreeteconomics.newyorkfed.org/2015/12/the-frbny-dsge-model-meets-julia.html).

This Julia-language implementation mirrors the MATLAB code
included in the Liberty Street Economics blog post
[The FRBNY DSGE Model Forecast](http://libertystreeteconomics.newyorkfed.org/2015/05/the-frbny-dsge-model-forecast-april-2015.html).

FRBNY is currently working on extending the code to include forecasts and other
features. Extensions of the DSGE model code may be released in the future at
the discretion of FRBNY.

# Model Design

*DSGE.jl* is an object-oriented approach to solving the FRBNY DSGE model that
takes advantage of Julia's type system, multiple dispatch, package-handling
mechanism, and other features. A single model object centralizes all information
about the model's parameters, states, equilibrium conditions, and settings in a
single data structure. The model object also keeps track of file locations for
all I/O operations.

The following objects define a model:

- __Parameters__: Have values, bounds, fixed-or-not status, priors. An
  instance of the `AbstractParameter` type houses all information about a given
  parameter in a single data structure.
- __States__: Mappings of names to indices (e.g. `π_t` ➜ 1).
- __Equilibrium Conditions__: A function that takes parameters and model
  indices, then returns `Γ0`, `Γ1`, `C`, `Ψ`, and `Π` (which fully describe the
  model in canonical form).
- __Measurement Equation__: A function mapping states to observables.

These are enough to define the model structure. _Everything else_ is essentially
a function of these basics, and we can solve the model and forecast observables
via the following chain:

- Parameters + Model Indices + Equilibrium conditions ➜ Transition matrices
  in state-space form
- Transition matrices + Data ➜ Estimated parameter values
- Estimated parameters + Transition matrices + Data ➜ Forecast (not yet
  implemented)

# Running the Code

## Running with Default Settings

So far, only the estimation step of the DSGE model has been implemented. To run
the estimation step in Julia, simply create an instance of the model object and
pass it to the `estimate` function.

```julia
# construct a model object
m = Model990()

# reoptimize parameter vector, compute Hessian at mode, and full posterior
# parameter sampling
estimate(m)

# produce LaTeX tables of parameter moments
compute_moments(m)
```

By default, the `estimate` routine reoptimizes the initial parameter vector,
computes the Hessian at the mode, and conducts full posterior parameter
sampling. (The initial parameter vector used is specified in the model's
constructor.)

The user may want to avoid reoptimizing the parameter vector and calculating the
Hessian matrix at this new vector. Please see [Reoptimizing](#reoptimizing)
below.

For more detail on changing the model's default settings, parameters, equilibrium
conditions, etc., see [Implementation Details](#implementation-details) for more specifics.

## Input/Output Directory Structure

The *DSGE.jl* estimation uses data files as input and produces large data files
as outputs. One estimation saves approximately 6GB of parameter draws and
related outputs. It is useful to understand how these files are loaded/saved
and how to control this behavior.

### Directory Tree
The following subdirectory tree indicates the default locations of
these input and outputs. Square brackets indicate directories in the tree that
will become relevant as future features are implemented.
- `<dataroot>/`: Root data directory.
  - `data/`:  Macroeconomic input data series.
    - `data_<yymmdd>.h5`: Input data vintage from `yymmdd`.
  - `cond/`: Conditional data, i.e.
    ["nowcast"](https://en.wikipedia.org/wiki/Nowcasting_%28economics%29), for
    the current forecast quarter.
  - `user/`: User-created or sample model input files. For instance, the user may
    specify a previously computed mode when `reoptimize(m)` is `false`, or a
    starting point for optimization when `reoptimize(m)` is `true`.
    - `paramsmode.h5`: Sample modal parameter vector.
    - `hessian.h5`: Sample Hessian matrix at mode.

- `<saveroot>/`: Root save directory.
  - `output_data/`
    - `m990/`: Input/output files for the `Model990` type. A model of type
      `SPEC` will create its own save directory `SPEC/` at this  level in the
      directory tree.
      - `ss0/`: Subdirectory for subspec 0.
        - `estimate/`
          - `figures/`: Plots and other figures
          - `tables/`: LaTeX tables
          - `raw/`: Raw output data from estimation step
            - `paramsmode.h5`: Parameter vector mode after running optimization
            - `hessian.h5`: Hessian at the mode
            - `mhsave.h5`: Draws from posterior distribution
          - `work/`: Derived data files created using `raw/` files as input
            - `cov.h5`: Covariance matrix for parameter draws from
              Metropolis-Hastings. Can be used as proposal covariance matrix.
        - [`xxx/`]: Other model outputs, such as forecasts, impulse response
          functions, and shock decompositions.
            - [`figures/`]: Plots and other figures
            - [`tables/`]: LaTeX tables
            - [`raw/`]: Raw output data from `xxx` step
            - [`work/`]: Derived data files created using `raw/` files as input
      - [`ss1/`] Additional model subspecs will have subdirectories identical to
        `ss0` at this level in the directory tree.

### Directory Paths

By default, input/output directories are located in the *DSGE.jl* package, along
with the source code. Default values of the input/output directory roots:
- `saveroot(m)`: `"$(Pkg.dir())/DSGE/save"`
- `dataroot(m)`: `"$(Pkg.dir())/DSGE/save/input_data"`

Note these locations can be overridden as desired:
```julia
m <= Setting(:saveroot, "path/to/my/save/root")
m <= Setting(:dataroot, "path/to/my/data/root")
```

# Input data used

For more details on the sample input data provided, please see
[Data](doc/Data.md).

For more details on using market interest rate expectations to treat the zero
lower bound, see
[Anticipated Policy Shocks](doc/AnticipatedPolicyShocks.md). In particular,
note that our model, as used to compute the forecasts referenced in Liberty
Street Economics posts,  is trained on data that includes six quarters of
interest rate expectations. The user is responsible for procuring interest rate
expectations and appending it to the provided sample data set, as discussed in
the linked documentation here.

# Implementation Details

This section describes important functions and implementation features in
greater detail. If the user is interested only in running the default model and
reproducing the forecast results, this section can be ignored.

This section focuses on what the code does and why, while the code itself
(including comments) provides detailed information regarding *how* these basic
procedures are implemented.

## Source Code Directory Structure

The source code directory structure follows Julia module conventions.

  - `doc/`: Code and model documentation
  - `src/`
     - `DSGE.jl`: The main module file.
     - `abstractdsgemodel.jl`: Defines the `AbstractModel` type.
     - `parameters.jl`: Implements the `AbstractParameter` type and its
       subtypes.
     - `settings.jl`: Implements the `Setting` type.
     - `distributions_ext.jl`: Defines additional functions to return objects of
       type Distribution.
     - `estimate/`: Mode-finding and posterior sampling.
     - [`xxx/`]: Other model functionality, such as forecasts, impulse response
       functions, and shock decompositions.
     - `models/`
           - `m990/`: Contains code to define and initialize version 990 of the
             FRBNY DSGE model.
              - `eqcond.jl`: Constructs `Model990` equilibrium condition
                matrices
              - `m990.jl`: Code for constructing a `Model990` object.
              - `measurement.jl`: Constructs `Model990` measurement equation
                matrices.
              - `subspecs.jl`: Code for model sub-specifications is defined
                here. See [Editing or Extending a Model](#editing-or-extending-a-model)
                for details on constructing model sub-specifications.
           - [`m991/`]: Code for new subtypes of `AbstractModel` should be kept
             in directories at this level in the directory tree
     - `solve/`: Solving the model; includes `gensys.jl` code.
  - `test/`: Module test suite.

## Reoptimizing

Generally, the user will want to reoptimize the parameter vector (and
consequently, calculate the Hessian at this new mode) every time they conduct
posterior sampling:
- the input data are updated with new observations or revised
- the model sub-specification is changed
- the model is derived from an existing model with differing equilibrium
  conditions or measurement equation.

This behavior can be controlled more finely.

### Reoptimize from Starting Vector

Reoptimize the model starting from the parameter values supplied in use
in a specified file. Ensure that you supply an HDF5 file with a variable named
`params` that is the correct dimension and data type.
```julia
m = Model990()
params = load_parameters_from_file(m, "path/to/parameter/file.h5")
update!(m, params)
estimate(m)
```

### Skip Reoptimization Entirely

You can provide a modal parameter vector and optionally a Hessian matrix
calculated at that mode to skip the reoptimization entirely. These values are
usually computed by the user previously.

You can skip reoptimization the parameter vector entirely.
```julia
m = Model990()
specify_mode!(m, "path/to/parameter/mode/file.h5")
estimate(m)
```
The `specify_mode!` function will update the parameter vector to the mode and
skip reoptimization. Ensure that you supply an HDF5 file with a variable named
`params` that is the correct dimension and data type.

You can additionally skip calculation of the Hessian matrix entirely.
```julia
m = Model990()
specify_mode!(m, "path/to/parameter/mode/file.h5")
specify_hessian(m, "path/to/Hessian/matrix/file.h5")
estimate(m)
```
The `specify_hessian` function will cause `estimate` to read in the Hessian
matrix rather than calculating it directly.  Ensure that you supply an HDF5
file with a variable named `hessian` that is the correct dimension and data
type. Specifying the Hessian matrix but *not* the parameter mode results in
undefined behavior.

## The `AbstractModel` Type and the Model Object

The `AbstractModel` type provides a common interface for all model objects,
which greatly facilitates the implementation of new model specifications. Any
concrete subtype of `AbstractModel` can be passed to any function defined for
`AbstractModel`, provided that the concrete type has the fields that the
function expects to be available.

`Model990` is one example of a concrete subtype of `AbstractModel` that
implements a single specification of the FRBNY DSGE model.
See [Editing or Extending a Model](#editing-or-extending-a-model).

### Parameters and Steady-States
- `parameters::Vector{AbstractParameter}`: Vector of all time-invariant model
  parameters.
- `steady_state::Vector`: Model steady-state values, computed as a function of
  elements of `parameters`.
- `keys::Dict{Symbol,Int}`: Maps human-readable names for all model parameters
  and steady-states to their indices in `parameters` and
  `steady_state`.

### Inputs to the Measurement and Equilibrium Condition Equations
- `endogenous_states::Dict{Symbol,Int}`: Maps each state to a column in the
  measurement and equilibrium condition matrices.
- `exogenous_shocks::Dict{Symbol,Int}`: Maps each shock to a column in the
  measurement and equilibrium condition matrices.
- `expected_shocks::Dict{Symbol,Int}`: Maps each expected shock to a column in
  the measurement and equilibrium condition matrices.
- `equilibrium_conditions::Dict{Symbol,Int}`: Maps each equilibrium condition to
  a row in the model's equilibrium condition matrices.
- `endogenous_states_augmented::Dict{Symbol,Int}`: Maps lagged states to their
  columns in the measurement and equilibrium condition equations. These are
  added after `gensys` solves the model.
- `observables::Dict{Symbol,Int}`: Maps each observable to a row in the model's
  measurement equation matrices.

### Model Specification and Settings
- `spec::ASCIIString`: Model specification number (e.g. `"m990"`). Identifies a
  particular set of parameters, equilibrium conditions, and measurement equation
  (equivalently, a concrete model type - for example, models of type `Model990`
  would have `spec = "m990"`.)
- `subspec::ASCIIString`: Model sub-specification (e.g. `"ss0"`). Indicates any
  changes to parameter initialization from `spec`.
  See [Editing or Extending a Model](#editing-or-extending-a-model) for more
  details.
- `settings::Dict{Symbol,Setting}`: Settings/flags that affect computation
  without changing the economic or mathematical setup of the model.
- `test_settings::Dict{Symbol,Setting}`: Settings/flags for testing mode

### Other Fields
- `rng::MersenneTwister`: Random number generator. By default, it is
  seeded to ensure reproducibility in algorithms that involve randomness
  (such as Metropolis-Hastings).
- `testing::Bool`: Indicates whether the model is in testing mode. If `true`,
  settings from `m.test_settings` are used in place of those in `m.settings`.
- `_filestrings::SortedDict{Symbol,AbstractString,ForwardOrdering}`: An
  alphabetized list of setting identifier strings. These are concatenated and
  appended to the filenames of all output files to avoid overwriting the output
  of previous estimations/forecasts that differ only in their settings, but not
  in their underlying mathematical structure. See [Settings](#model-settings)
  for more details.

## Defining Indices

The model's equilibrium conditions and observables are represented as fairly
large matrices, and keeping track of which rows and columns correspond to which
states, shocks, equations, etc. can be confusing. To improve clarity, we define
several dictionaries that map variable names to indices in these matrices:

- `endogenous_states`: Indices of endogenous model states
- `exogenous_shocks`: Indices of exogenous shocks
- `expected_shocks`: Indices of expectation shocks
- `equilibrium_conditions`: Indices of equilibrium condition equations
- `endogenous_states_augmented`: Indices of model states, after model solution
  and system augmentation
- `observables`:  Indices of named observables

This approach has a number of advantages. Most importantly, it is robust to
inadvertent typos or indexing errors. Since the actual index number doesn't
matter to us, the user only needs to define the names of their equilibrium
conditions, states, and other variables. Adding states is easy - we have only to
add them to the appropriate list in the model constructor, and they will be
assigned an index.

As an example, consider the model's equilibrium conditions. The canonical
representation of the equilibrium conditions is

```
Γ0 s_t = Γ1 s_{t-1} + C + Ψ ε_t + Π η_t
```

where `Γ0`, `Γ1`, `C`, `Ψ`, and `Π` are matrices of coefficients for `s_t`
(states at time `t`), `s_{t-1}` (lagged states), `ε_t` (exogenous shocks) and
`η_t` (expectational shocks). Each row of these matrices corresponds to an
equilibrium condition, which we define using a descriptive name (for example, we
name the consumption Euler equation `:euler`). States (columns of `Γ0` and
`Γ1`), exogenous shocks (columns of `Ψ`), and expectational shocks (columns
`Π`) also have names.

## Parameters: The `AbstractParameter` Type

The `AbstractParameter` type implements our notion of a model parameter: a
time-invariant, unobserved value that has economic significance in the model's
equilibrium conditions. We estimate the model to find the values of these
parameters.

Though all parameters are time-invariant, each has different features. Some
parameters are scaled for use in the model's equilibrium conditions and
measurement equations.  During optimization, parameters can be transformed from
model space to the real line via one of three different transformations. These
transformations are also defined as types, and require additional information
for each parameter. Finally, steady-state parameters are not estimated directly,
but are calculated as a function of other parameters.

These various requirements are nicely addressed using a parameterized type
hierarchy.

- `AbstractParameter{T<:Number}`: The common abstract supertype for all
  parameters.
    - `Parameter{T<:Number, U<:Transform}`: The abstract supertype for
      parameters that are directly estimated.
        - `UnscaledParameter{T<:Number, U:<Transform}`: Concrete type for
          parameters that do not need to be scaled for equilibrium conditions.
        - `ScaledParameter{T<:Number, U:<Transform}`: Concrete type for
          parameters that are scaled for equilibrium conditions.
    - `SteadyStateParameter{T<:Number}`: Concrete type for steady-state
      parameters.

All `Parameter`s have the following fields:

- `key::Symbol`: Parameter name. For maximum clarity, `key` should conform to
  the guidelines established in [CONTRIBUTING.md](CONTRIBUTING.md).
- `value::T`: Parameter value. Initialized in model space (guaranteed to be
  between `valuebounds`), but can be transformed between model space and the
  real line via calls to `transform_to_real_line` and
  `transform_to_model_space`.
- `valuebounds::Interval{T}`: Bounds for the parameter's value in model space.
- `transform_parameterization::Interval{T}`: Parameters used to transform
  `value` between model space and the real line.
- `transform::U`: Transformation used to transform `value` between model space
  and real line.
- `prior::NullablePrior`: Prior distribution for parameter value.
- `fixed::Bool`: Indicates whether the parameter's value is fixed rather than
  estimated.
- `description::AbstractString`: A short description of the parameter's economic
  significance.
- `tex_label::AbstractString`: String for printing the parameter name to LaTeX.

`ScaledParameters` also have the following fields:

- `scaledvalue::T`: Parameter value scaled for use in `eqcond.jl`
- `scaling::Function`: Function used to scale parameter value for use in
  equilibrium conditions.

*Note:* Though not strictly necessary, defining a scaling with the parameter
object allows for much a much cleaner definition of the equilibrium conditions.

Because the values of `SteadyStateParameter`s are directly computed as a
function of `ScaledParameter`s and `UnscaledParameter`s, they only require 4
fields:

- `key::Symbol`
- `value::T`
- `description::AbstractString`
- `tex_label::AbstractString`

## Model Settings

The `Setting` type implements computational settings that affect how the code
runs without affecting the mathematical definition of the model. These include
flags (e.g. whether or not to recompute the Hessian), parameterization for the
Metropolis-Hastings algorithm (e.g. number of times to draw from the posterior
distribution), and the vintage of data being used (`Setting` is a parametric
type - a `Setting{T<:Any}`, so Booleans, Numbers, and Strings can all be turned
into `Setting`s). They are stored centrally in the `settings` dictionary within
the model object.

Why implement a `Setting` type when we could put their values directly into the
source code or dictionary? The most obvious answer is that the parametric type
allows us to implement a single interface for all `Setting`s (Booleans, Strings,
etc.), so that when we access a particular setting during the estimation and
forecast steps, we don't have to think about the setting's type.

`Setting`s play an important role in addition to providing useful abstraction.
Estimating and forecasting the FRBNY DSGE model takes many hours of computation
time and creates a lot of output files. It is useful to be able to compare model
output from two different models whose settings differ slightly (for example,
consider two identical models that use different vintages of data as input). A
central feature of the `Setting` type is a mechanism that generates unique,
meaningful filenames when code is executed with different settings.
Specifically, when a setting takes on a non-default value, a user-defined
setting code (along with the setting's value) are appended to all output files
generated during execution.

The `Setting{T<:Any}` type has the following fields:

- `key::Symbol`: Name of setting
- `value::T`: Value of setting
- `print::Bool`: Indicates whether to append this setting's code and value to
  output file names. If true, output file names will include a suffix of the
  form `_key1=val1_key2=val2` etc. where codes are listed in alphabetical order.
- `code::AbstractString`: short string (4 characters or less) to print to output
  file names when `print=true`.
- `description::AbstractString`: Short description of what the setting is used
  for.

### Default Settings

#### I/O

- `dataroot::Setting{ASCIIString}`: The root directory for
  model input data.
- `saveroot::Setting{ASCIIString}`: The root directory for model output.
- `data_vintage::Setting{ASCIIString}`: Data vintage identifier, formatted
  `yymmdd`. By default, `data_vintage` is set to the most recent date of the
  files with name `<dataroot>/data/data_<yymmdd>.h5`. It is the only setting
  printed to output filenames by default.

#### Anticipated Shocks
- `n_anticipated_shocks::Setting{Int}`: Number of anticipated policy shocks.
- `n_anticipated_shocks_padding::Setting{Int}`: Padding for anticipated shocks.
- `zlb_start_index::Setting{Int}`: Index into input data matrix of first period
  to incorporate zero bound expectations. The first observation in the sample
  data is 1959Q3 and we assume the zero lower bound period starts in 2008Q4, so
  we set this to `198` by default.
- `n_presample_periods::Setting{Int}`: Number of periods in the presample.

#### Estimation
- `reoptimize::Setting{Bool}`: Whether to reoptimize the posterior mode. If
  `true` (the default), `estimate()` begins reoptimizing from the model object's
  parameter vector.
- `calculate_hessian::Setting{Bool}`: Whether to compute the Hessian. If `true`
  (the default), `estimate()` calculates the Hessian at the posterior mode.

#### Metropolis-Hastings
- `n_mh_simulations::Setting{Int}`: Number of draws from the posterior
  distribution per block.
- `n_mh_blocks::Setting{Int}`: Number of blocks to run Metropolis-Hastings.
- `n_mh_burn::Setting{Int}`: Number of blocks to discard as burn-in for
  Metropolis-Hastings.
- `mh_thin::Setting{Int}`: Metropolis-Hastings thinning step.

### Accessing Settings
The function `get_setting(m::AbstractModel, s::Symbol)` returns the value of the
setting `s` in `m.settings`. Some settings also have explicit getter methods
that take only the model object `m` as an argument:

*I/O settings:*
`saveroot(m)`,
`dataroot(m)`,
`data_vintage(m)`,

*Parallelization*:
`use_parallel_workers(m)`

*Estimation*:
`reoptimize(m)`,
`calculate_hessian(m)`,
`n_hessian_test_params(m)`,

*Metropolis-Hastings*:
`n_mh_blocks(m)`,
`n_mh_simulations(m)`,
`n_mh_burn(m)`,
`mh_thin(m)`

### Overwriting Default Settings

To overwrite default settings added during model construction, a user must
define a new `Setting` object and overwrite the corresponding entry in the
model's `settings` dictionary using the `<=` syntax. Individual fields of a
pre-initialized setting object cannot be modified. This immutability enforces
the naming convention described in the preceding paragraphs (the default
parameters are constructed without codes and are not printed to filename outputs
to avoid excessively long filenames). Therefore, we strongly suggest that users
who modify settings set `print=true` and define a meaningful code when
overwriting any default settings.

For example, overwriting `use_parallel_workers` should look like this:
```julia
m = Model990()
m <= Setting(:use_parallel_workers, true)
```

## Estimation

Finds modal parameter values, calculate Hessian matrix at mode, and samples
from posterior distribution. See `estimate` in
[estimate.jl](src/estimate/estimate.jl).

**Main Steps**:

- *Initialization*: Read in and transform raw data from `save/input_data/`.

- *Reoptimize parameter vector*: The main program will call the `csminwel`
  optimization routine (located in `csminwel.jl`) to find modal parameter
  estimates.

- *Compute Hessian matrix*: Computing the Hessian matrix to scale the
  proposal distribution in the Metropolis-Hastings algorithm.

- *Sample from Posterior*: Posterior sampling is performed using the
  Metropolis-Hastings algorithm. A proposal distribution is constructed centered
  at the posterior mode and with proposal covariance scaled by the inverse of
  the Hessian matrix. Settings for the number of sampling blocks and the size of
  those blocks can be altered as described in
  [Editing or Extending a Model](#editing-or-extending-a-model).

**Remark**: In addition to saving each `mh_thin`-th draw of the parameter
vector, the estimation program also saves the resulting posterior value and
transition equation matrices implied by each draw of the parameter vector. This
is to save time in the forecasting step since that code can avoid recomputing
those matrices.

# Editing or Extending a Model

Users may want to extend or edit `Model990` in a number of different ways.
The most common changes are listed below, in decreasing order of complexity:

1. Add new parameters
2. Modify equilibrium conditions or measurement equations
3. Change the values of various parameter fields (i.e. initial `value`,
   `prior`, `transform`, etc.)
4. Change the values of various computational settings (i.e. `reoptimize`,
   `n_mh_blocks`)

Points 1 and 2 often go together (adding a new parameter guarantees a change in
equilibrium conditions), and are such fundamental changes that they increment
the model specification number and require the definition of a new subtype of
`AbstractModel` (for instance, `Model991`).
See [Model specification](#model-specification-mspec) for more details.

Any changes to the initialization of preexisting parameters are defined as a new
model *sub-specification*, or *subspec*. While less significant than a change to
the model's equilibrium conditions, changing the values of some parameter fields
(especially priors) can have economic significance over and above settings we
use for computational purposes. **Parameter definitions should not be modified
in the model object's constructor.** First, incrementing the model's
sub-specification number when parameters are changed improves model-level (as
opposed to code-level) version control. Second, it avoids potential output
filename collisions, preventing the user from overwriting output from previous
estimations with the original parameters. The protocol for defining new
sub-specifications is described in
[Model sub-specifications](#model-sub-specifications-msubspec).

Overriding default settings is described in the [Settings](#model-settings)
section above.

## Model specification (`m.spec`)

A particular model, which corresponds to a subtype of `AbstractModel`, is
defined as a set of parameters, equilibrium conditions (defined by the `eqcond`
function) and measurement equations (defined by the `measurement` function).
Therefore, the addition of new parameters, states, or observables, or any
changes to the equilibrium conditions or measurement equations necessitate the
creation of a new subtype of `AbstractModel.`

To create a new model object, we recommend doing the following:

1. Duplicate the `m990` directory within the [models](src/models/) directory. Name the
new directory `mXXX.jl`, where `XXX` is your chosen model specification number
or string.  Rename `m990.jl` in this directory to `mXXX.jl`.

2. In the `mXXX/` directory, change all references to `Model990` to `ModelXXX`.

3. Edit the `m990.jl`, `eqcond.jl`, and `measurement.jl` files as you see fit.
If adding new states, equilibrium conditions, shocks, or observables, be sure to
add them to the appropriate list in `init_model_indices`.

4. Open the module file, `src/DSGE.jl`. Add `ModelXXX` to the list of functions
to export, and include each of the files in `src/model/mXXX`.

## Model sub-specifications (`m.subspec`)

`Model990` sub-specifications are initialized by overwriting initial parameter
definitions before the model object is fully constructed. This happens via a
call to `init_subspec` in the `Model990` constructor. (Clearly, an identical
protocol should be followed for new model types as well.)

To create a new sub-specification (e.g., subspec 1) of `Model990`, edit the file
`src/models/subspecs.jl` as follows (note that this example is not actually
sub-specification `1` of `Model990`. In the source code, our sub-specification
`5` is provided as additional example.):

1. Define a new function, `ss1`, that takes an object of type `Model990` (not
`AbstractModel`!) as an argument. In this function, construct new parameter
objects and overwrite existing model parameters using the `<=` syntax. For
example,

```julia
function ss1(m::Model990)
    m <= parameter(:ι_w, 0.000, (0.0, .9999), (0.0,0.9999), DSGE.Untransformed(), Normal(0.0,1.0), fixed=false,
                   description="ι_w: Some description.",
                   tex_label="\\iota_w")
    m <= parameter(:ι_p, 0.0, fixed=true,
                   description= "ι_p: Some description"
                   tex_label="\\iota_p")
end
```

2. Add an `elseif` condition to `init_subspec`:

```julia
    ...
    elseif subspec(m) == "ss1"
        return ss1(m)
    ...
```

To construct an instance of `Model990`, `ss1`, call the constructor
for `Model990` with `ss1` as an argument. For example,

```julia
m = Model990("ss1")
```

## Acknowledgements
Developers of this package at [FRBNY](https://www.newyorkfed.org/research)
include

* [Pearl Li](https://github.com/pearlzli)
* [Erica Moszkowski](https://github.com/emoszkowski)
* [Micah Smith](https://github.com/micahjsmith)

Contributors to this package at [QuantEcon](http://quantecon.org) include

* [Zac Cranko](https://github.com/ZacCranko)
* [Spencer Lyon](https://github.com/spencerlyon2)
* [Pablo Winant](http://www.mosphere.fr/)

The `gensys` and `csminwel` routines in [gensys.jl](src/solve/gensys.jl) and
[csminwel.jl](src/estimate/csminwel.jl) are based on routines originally
copyright [Chris Sims](http://www.princeton.edu/~sims). The files are released
here with permission of Chris Sims under the BSD-3 [license](LICENSE).

The `kalman_filter` routine is loosely based on a version of the
Kalman filter algorithm originally copyright Federal Reserve Bank of Atlanta
and written by [Iskander Karibzhanov](http://karibzhanov.com). The files are
released here with permission of the Federal Reserve Bank of Atlanta under the
BSD-3 [license](LICENSE).
