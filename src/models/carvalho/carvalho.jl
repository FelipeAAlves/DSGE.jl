"""
```
Carvalho{T} <: AbstractModel{T}
```

The `Carvalho` type defines the structure of the FRBNY DSGE model.

### Fields

#### Parameters and Steady-States
* `parameters::Vector{AbstractParameter}`: Vector of all time-invariant model parameters.

* `steady_state::Vector`: Model steady-state values, computed as a function of elements of
  `parameters`.

* `keys::Dict{Symbol,Int}`: Maps human-readable names for all model parameters and
  steady-states to their indices in `parameters` and `steady_state`.

#### Inputs to Measurement and Equilibrium Condition Equations

The following fields are dictionaries that map human-readible names to row and column
indices in the matrix representations of of the measurement equation and equilibrium
conditions.

* `endogenous_states::Dict{Symbol,Int}`: Maps each state to a column in the measurement and
  equilibrium condition matrices.

* `exogenous_shocks::Dict{Symbol,Int}`: Maps each shock to a column in the measurement and
  equilibrium condition matrices.

* `expected_shocks::Dict{Symbol,Int}`: Maps each expected shock to a column in the
  measurement and equilibrium condition matrices.

* `equilibrium_conditions::Dict{Symbol,Int}`: Maps each equlibrium condition to a row in the
  model's equilibrium condition matrices.

* `endogenous_states_augmented::Dict{Symbol,Int}`: Maps lagged states to their columns in
  the measurement and equilibrium condition equations. These are added after Gensys solves the
  model.

* `observables::Dict{Symbol,Int}`: Maps each observable to a row in the model's measurement
  equation matrices.

#### Model Specifications and Settings

* `spec::AbstractString`: The model specification identifier, "carvalho", cached here for
  filepath computation.

* `subspec::AbstractString`: The model subspecification number, indicating that some
  parameters from the original model spec ("ss0") are initialized differently. Cached here for
  filepath computation.

* `settings::Dict{Symbol,Setting}`: Settings/flags that affect computation without changing
  the economic or mathematical setup of the model.

* `test_settings::Dict{Symbol,Setting}`: Settings/flags for testing mode

#### Other Fields

* `rng::MersenneTwister`: Random number generator. Can be is seeded to ensure
  reproducibility in algorithms that involve randomness (such as Metropolis-Hastings).

* `testing::Bool`: Indicates whether the model is in testing mode. If `true`, settings from
  `m.test_settings` are used in place of those in `m.settings`.

* `_filestrings::SortedDict{Symbol,AbstractString,ForwardOrdering}`: An alphabetized list of
  setting identifier strings. These are concatenated and appended to the filenames of all
  output files to avoid overwriting the output of previous estimations/forecasts that differ
  only in their settings, but not in their underlying mathematical structure.
"""
type Carvalho{N,T} <: AbstractModel{T}
    parameters::ParameterVector{T}                  # vector of all time-invariant model parameters
    steady_state::ParameterVector{T}                # model steady-state values
    keys::Dict{Symbol,Int}                          # human-readable names for all the model
                                                    # parameters and steady-n_states

    endogenous_states::Dict{Symbol,Int}             # these fields used to create matrices in the
    exogenous_shocks::Dict{Symbol,Int}              # measurement and equilibrium condition equations.
    expected_shocks::Dict{Symbol,Int}               #
    equilibrium_conditions::Dict{Symbol,Int}        #
    endogenous_states_augmented::Dict{Symbol,Int}   #
    observables::Dict{Symbol,Int}                   #

    spec::ASCIIString                               # Model specification number (eg "carvalho")
    subspec::ASCIIString                            # Model subspecification (eg "ss0")
    settings::Dict{Symbol,Setting}                  # Settings/flags for computation
    test_settings::Dict{Symbol,Setting}             # Settings/flags for testing mode
    rng::MersenneTwister                            # Random number generator
    testing::Bool                                   # Whether we are in testing mode or not
    _filestrings::SortedDict{Symbol,AbstractString, ForwardOrdering} # The strings we will print to a filename
end

description(m::Carvalho) = "CarvalhoLee multi-sector sticky price DSGE model, $(m.subspec)"

"""
`init_model_indices!(m::Carvalho)`

Arguments:
`m:: Carvalho`: a model object

Description:
Initializes indices for all of `m`'s states, shocks, and equilibrium conditions.
"""
function init_model_indices!(m::Carvalho{N,T})

    # Endogenous states
    endogenous_states = [[
        :c_t, :π_t, :i_t, :h_t, :wp_t, :z_t,
        :γ_t, :a_t, :μ_t,
        :Ec_t, :Eπ_t, :Eγ_t];
        [symbol("ck$n_t") for n in 1:N];
        [symbol("πk$n_t") for n in 1:N];
        [symbol("Eπk$n_t") for n in 1:N];
        [symbol("ak$n_t") for n in 1:N];
        [symbol("dk$n_t") for n in 1:N]]

    # Exogenous shocks
    exogenous_shocks = [
        :γ_sh, :a_sh, :μ_sh];
        [symbol("ak$n_sh") for n in 1:N];
        [symbol("dk$n_sh") for n in 1:N]]

    # Expectations shocks
    expected_shocks = [[
        :η_c, :η_π, :η_γ];
        [symbol("η_πk$n") for n in 1:N]]

    # Equilibrium conditions
    equilibrium_conditions = [[
        :eq_euler, :eq_lab, :eq_aggsup, :eq_costmin, :eq_Π, :eq_taylor];
        [symbol("eq_pck$n") for n in 1:N];
        [symbol("eq_demk$n") for n in 1:N];
        [:eq_γ, :eq_a, :eq_μ];
        [symbol("eq_ak$n") for n in 1:N];
        [symbol("eq_dk$n") for n in 1:N]]

    # Additional states added after solving model
    # Lagged states and observables measurement error
    endogenous_states_augmented = []

    # Measurement equation observables
    observables = [[
        :obs_int,              # quarterly output growth
        :obs_hours];            # aggregate hours growth
        [symbol("obs_πk$n") for n in 1:N];
        [symbol("obs_ck$n") for n in 1:N]]

    for (i,k) in enumerate(endogenous_states);            m.endogenous_states[k]            = i end
    for (i,k) in enumerate(exogenous_shocks);             m.exogenous_shocks[k]             = i end
    for (i,k) in enumerate(expected_shocks);              m.expected_shocks[k]              = i end
    for (i,k) in enumerate(equilibrium_conditions);       m.equilibrium_conditions[k]       = i end
    for (i,k) in enumerate(endogenous_states);            m.endogenous_states[k]            = i end
    for (i,k) in enumerate(endogenous_states_augmented);  m.endogenous_states_augmented[k] = i+length(endogenous_states) end
    for (i,k) in enumerate(observables);                  m.observables[k]                  = i end
end


function Carvalho(N::Int64, subspec::AbstractString="ss2")

    # Model-specific specifications
    spec               = split(basename(@__FILE__),'.')[1]
    subspec            = subspec
    settings           = Dict{Symbol,Setting}()
    test_settings      = Dict{Symbol,Setting}()
    rng                = MersenneTwister()
    testing            = false
    _filestrings       = SortedDict{Symbol,AbstractString, ForwardOrdering}()

    # initialize empty model
    m = Carvalho{N,Float64}(
            # model parameters and steady state values
            Vector{AbstractParameter{Float64}}(), Vector{Float64}(), Dict{Symbol,Int}(),

            # model indices
            Dict{Symbol,Int}(), Dict{Symbol,Int}(), Dict{Symbol,Int}(), Dict{Symbol,Int}(), Dict{Symbol,Int}(), Dict{Symbol,Int}(),

            spec,
            subspec,
            settings,
            test_settings,
            rng,
            testing,
            _filestrings)

    # Set settings
    settings_carvalho(m)
    default_test_settings(m)

    # Initialize parameters
    if N == 3
        m <= parameter(:n1 , 0.3, fixed = true,
                       description = "measure of sector ", tex_label = "n_1")
    end

    ## Parameters to include


    α = AbstractParameter{Float64}[
        parameter(symbol("αk$n"), 0.50, fixed = true,
                  description="αk$n: rigidity on sector $n", tex_label = "\\alpha_k")
                  for n in 1:N]
    m <= parameter(:α,      0.1596, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     Normal(0.30, 0.05),         fixed=false,
                   description="α: Capital elasticity in the intermediate goods sector's production function (also known as the capital share).",
                   tex_label="\\alpha")

    m <= parameter(:ζ_p,   0.8940, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.5, 0.1),          fixed=false,
                   description="ζ_p: The Calvo parameter. In every period, intermediate goods producers optimize prices with probability (1-ζ_p). With probability ζ_p, prices are adjusted according to a weighted average of the previous period's inflation (π_t1) and steady-state inflation (π_star).",
                   tex_label="\\zeta_p")

    m <= parameter(:ι_p,   0.1865, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.5, 0.15),         fixed=false,
                   description="ι_p: The weight attributed to last period's inflation in price indexation. (1-ι_p) is the weight attributed to steady-state inflation.",
                   tex_label="\\iota_p")

    m <= parameter(:δ,      0.025,  fixed=true,
                   description="δ: The capital depreciation rate.", tex_label="\\delta" )

    m <= parameter(:Upsilon,  1.000,  (0., 10.),     (1e-5, 0.),      DSGE.Exponential(),    GammaAlt(1., 0.5),          fixed=true,
                   description="Υ: The trend evolution of the price of investment goods relative to consumption goods. Set equal to 1.",
                   tex_label="\\mathcal{\\Upsilon}")

    m <= parameter(:Φ,   1.1066, (1., 10.),     (1.00, 10.00),   DSGE.Exponential(),    Normal(1.25, 0.12),         fixed=false,
                   description="Φ: Fixed costs.",
                   tex_label="\\Phi")

    m <= parameter(:S′′,       2.7314, (-15., 15.),   (-15., 15.),     DSGE.Untransformed(),  Normal(4., 1.5),            fixed=false,
                   description="S'': The second derivative of households' cost of adjusting investment.", tex_label="S\\prime\\prime")

    m <= parameter(:h,        0.5347, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.7, 0.1),          fixed=false,
                   description="h: Consumption habit persistence.", tex_label="h")

    m <= parameter(:ppsi,     0.6862, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.5, 0.15),         fixed=false,
                   description="ppsi: Utilization costs.", tex_label="ppsi")

    m <= parameter(:ν_l,     2.5975, (1e-5, 10.),   (1e-5, 10.),     DSGE.Exponential(),    Normal(2, 0.75),            fixed=false,
                   description="ν_l: The coefficient of relative risk aversion on the labor
                   term of households' utility function.", tex_label="\\nu_l")

    m <= parameter(:ζ_w,   0.9291, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.5, 0.1),          fixed=false,
                   description="ζ_w: (1-ζ_w) is the probability with which households can freely choose wages in each period. With probability ζ_w, wages increase at a geometrically weighted average of the steady state rate of wage increases and last period's productivity times last period's inflation.",
                   tex_label="\\zeta_w")

    m <= parameter(:ι_w,   0.2992, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.5, 0.15),         fixed=false,
                   description="ι_w: No description available.",
                   tex_label="\\iota_w")

    m <= parameter(:λ_w,      1.5000,                                                                               fixed=true,
                   description="λ_w: The wage markup, which affects the elasticity of substitution between differentiated labor services.",
                   tex_label="\\lambda_w")

    m <= parameter(:β,      0.1402, (1e-5, 10.),   (1e-5, 10.),     DSGE.Exponential(),    GammaAlt(0.25, 0.1),        fixed=false,  scaling = x -> 1/(1 + x/100),
                   description="β: Discount rate.",
                   tex_label="\\beta ")

    m <= parameter(:ψ1,     1.3679, (1e-5, 10.),   (1e-5, 10.00),   DSGE.Exponential(),    Normal(1.5, 0.25),          fixed=false,
                   description="ψ₁: Weight on inflation gap in monetary policy rule.",
                   tex_label="\\psi_1")

    m <= parameter(:ψ2,     0.0388, (-0.5, 0.5),   (-0.5, 0.5),     DSGE.Untransformed(),  Normal(0.12, 0.05),         fixed=false,
                   description="ψ₂: Weight on output gap in monetary policy rule.",
                   tex_label="\\psi_2")

    m <= parameter(:ψ3,     0.2464, (-0.5, 0.5),   (-0.5, 0.5),     DSGE.Untransformed(),  Normal(0.12, 0.05),         fixed=false,
                   description="ψ₃: Weight on rate of change of output gap in the monetary policy rule.",
                   tex_label="\\psi_3")

    m <= parameter(:π_star,   0.5000, (1e-5, 10.),   (1e-5, 10.),     DSGE.Exponential(),    GammaAlt(0.75, 0.4),        fixed=true,  scaling = x -> 1 + x/100,
                   description="π_star: The steady-state rate of inflation.",
                   tex_label="\\pi_*")

    m <= parameter(:σ_c,   0.8719, (1e-5, 10.),   (1e-5, 10.),     DSGE.Exponential(),    Normal(1.5, 0.37),          fixed=false,
                   description="σ_c: No description available.",
                   tex_label="\\sigma_{c}")

    m <= parameter(:ρ,      0.7126, (1e-5, 0.999), (1e-5, 0.999),   DSGE.SquareRoot(),     BetaAlt(0.75, 0.10),        fixed=false,
                   description="ρ: The degree of inertia in the monetary policy rule.",
                   tex_label="\\rho")

    m <= parameter(:ϵ_p,     10.000,                                                                               fixed=true,
                   description="ϵ_p: No description available.",
                   tex_label="\\varepsilon_{p}")

    m <= parameter(:ϵ_w,     10.000,                                                                               fixed=true,
                   description="ϵ_w: No description available.",
                   tex_label="\\varepsilon_{w}")

    # financial frictions parameters
    m <= parameter(:Fω,      0.0300, (1e-5, 0.99999), (1e-5, 0.99),  DSGE.SquareRoot(),    BetaAlt(0.03, 0.01),         fixed=true,    scaling = x -> 1 - (1-x)^0.25,
                   description="F(ω): The cumulative distribution function of ω (idiosyncratic iid shock that increases or decreases entrepreneurs' capital).",
                   tex_label="F(\\omega)")

    m <= parameter(:spr,     1.7444, (0., 100.),      (1e-5, 0.),    DSGE.Exponential(),   GammaAlt(2., 0.1),           fixed=false,  scaling = x -> (1 + x/100)^0.25,
                   description="spr_*: No description available.",
                   tex_label="spr_*")

    m <= parameter(:ζ_spb, 0.0559, (1e-5, 0.99999), (1e-5, 0.99),  DSGE.SquareRoot(),    BetaAlt(0.05, 0.005),        fixed=false,
                   description="ζ_spb: The elasticity of the expected exess return on capital (or 'spread') with respect to leverage.",
                   tex_label="\\zeta_{spb}")

    m <= parameter(:γ_star, 0.9900, (1e-5, 0.99999), (1e-5, 0.99),  DSGE.SquareRoot(),    BetaAlt(0.99, 0.002),        fixed=true,
                   description="γ_star: No description available.",
                   tex_label="\\gamma_*")

    # exogenous processes - level
    m <= parameter(:γ,      0.3673, (-5.0, 5.0),     (-5., 5.),     DSGE.Untransformed(), Normal(0.4, 0.1),            fixed=false, scaling = x -> x/100,
                   description="γ: The log of the steady-state growth rate of technology.",
                   tex_label="\\gamma")

    m <= parameter(:Lmean,  -45.9364, (-1000., 1000.), (-1e3, 1e3),   DSGE.Untransformed(), Normal(-45, 5),              fixed=false,
                   description="Lmean: No description available.",
                   tex_label="Lmean")

    m <= parameter(:g_star,    0.1800,                                                                               fixed=true,
                   description="g_star: No description available.",
                   tex_label="g_*")

    # exogenous processes - autocorrelation
    m <= parameter(:ρ_g,      0.9863, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_g: AR(1) coefficient in the government spending process.",
                   tex_label="\\rho_g")

    m <= parameter(:ρ_b,      0.9410, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_b: AR(1) coefficient in the intertemporal preference shifter process.",
                   tex_label="\\rho_b")

    m <= parameter(:ρ_μ,     0.8735, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_μ: AR(1) coefficient in capital adjustment cost process.",
                   tex_label="\\rho_{\\mu}")

    m <= parameter(:ρ_z,      0.9446, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_z: AR(1) coefficient in the technology process.",
                   tex_label="\\rho_z")

    m <= parameter(:ρ_λ_f,    0.8827, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_λ_f: AR(1) coefficient in the price mark-up shock process.",
                   tex_label="\\rho_{\\lambda_f}")

    m <= parameter(:ρ_λ_w,    0.3884, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_λ_w: AR(1) coefficient in the wage mark-up shock process.",
                   tex_label="\\rho_{\\lambda_w}")

    #monetary policy shock - see eqcond
    m <= parameter(:ρ_rm,     0.2135, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false,
                   description="ρ_rm: AR(1) coefficient in the monetary policy shock process.",
                   tex_label="\\rho_{rm}")

    m <= parameter(:ρ_σ_w,   0.9898, (1e-5, 0.99999), (1e-5, 0.99),  DSGE.SquareRoot(),    BetaAlt(0.75, 0.15),         fixed=false,
                   description="ρ_σ_w: The standard deviation of entrepreneurs' capital productivity follows an exogenous process with mean ρ_σ_w. Innovations to the process are called _spread shocks_.",
                   tex_label="\\rho_{\\sigma_\\omega}")

    m <= parameter(:ρ_μ_e,    0.7500, (1e-5, 0.99999), (1e-5, 0.99),  DSGE.SquareRoot(),    BetaAlt(0.75, 0.15),         fixed=true,
                   description="ρ_μ_e: Verification costs are a fraction μ_e of the amount the bank extracts from an entrepreneur in case of bankruptcy???? This doesn't seem right because μ_e isn't a process (p12 of PDF)",
                   tex_label="\\rho_{\\mu_e}")

    m <= parameter(:ρ_γ,   0.7500, (1e-5, 0.99999), (1e-5, 0.99),  DSGE.SquareRoot(), BetaAlt(0.75, 0.15),         fixed=true,  description="ρ_γ: No description available.",              tex_label="\\rho_{\\gamma}")
    m <= parameter(:ρ_π_star,   0.9900, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(), BetaAlt(0.5, 0.2),           fixed=true,  description="ρ_π_star: No description available.",         tex_label="\\rho_{\\pi^*}")
    m <= parameter(:ρ_lr,     0.6936, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false, description="ρ_lr: No description available.",             tex_label="\\rho_{lr}")
    m <= parameter(:ρ_z_p,     0.8910, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false, description="ρ_z_p: No description available.",             tex_label="\\rho_{z^p}")
    m <= parameter(:ρ_tfp,    0.1953, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false, description="ρ_tfp: No description available.",            tex_label="\\rho_{tfp}")
    m <= parameter(:ρ_gdpdef, 0.5379, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false, description="ρ_gdpdef: GDP deflator.",                            tex_label="\\rho_{gdpdef}")
    m <= parameter(:ρ_corepce,    0.2320, (1e-5, 0.999),   (1e-5, 0.999), DSGE.SquareRoot(),    BetaAlt(0.5, 0.2),           fixed=false, description="ρ_corepce: No description available.",            tex_label="\\rho_{corepce}")

    # exogenous processes - standard deviation
    m <= parameter(:σ_g,      2.5230, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_g: The standard deviation of the government spending process.",
                   tex_label="\\sigma_{g}")

    m <= parameter(:σ_b,      0.0292, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_b: No description available.",
                   tex_label="\\sigma_{b}")

    m <= parameter(:σ_μ,     0.4559, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_μ: The standard deviation of the exogenous marginal efficiency of investment shock process.",
                   tex_label="\\sigma_{\\mu}")

    m <= parameter(:σ_z,      0.6742, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_z: No description available.",
                   tex_label="\\sigma_{z}")

    m <= parameter(:σ_λ_f,    0.1314, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_λ_f: The mean of the process that generates the price elasticity of the composite good.  Specifically, the elasticity is (1+λ_{f,t})/(λ_{f_t}).",
                   tex_label="\\sigma_{\\lambda_f}")

    m <= parameter(:σ_λ_w,    0.3864, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_λ_w: No description available.",
                   tex_label="\\sigma_{\\lambda_w}")

    m <= parameter(:σ_r_m,     0.2380, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false,
                   description="σ_r_m: No description available.",
                   tex_label="\\sigma_{rm}")

    m <= parameter(:σ_σ_ω,   0.0428, (1e-7,100.),     (1e-5, 0.),    DSGE.Exponential(),   RootInverseGamma(4., 0.05),  fixed=false,
                   description="σ_σ_ω: The standard deviation of entrepreneurs' capital productivity follows an exogenous process with standard deviation σ_σ_ω.",
                   tex_label="\\sigma_{\\sigma_\\omega}")

    m <= parameter(:σ_μ_e,    0.0000, (1e-7,100.),     (1e-5, 0.),    DSGE.Exponential(), RootInverseGamma(4., 0.05),  fixed=true,  description="σ_μ_e: No description available.",           tex_label="\\sigma_{\\mu_e}")
    m <= parameter(:σ_γ,   0.0000, (1e-7,100.),     (1e-5, 0.),    DSGE.Exponential(),   RootInverseGamma(4., 0.01),  fixed=true,  description="σ_γ: No description available.",             tex_label="\\sigma_{\\gamma}")
    m <= parameter(:σ_π_star,   0.0269, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(), RootInverseGamma(6., 0.03),  fixed=false, description="σ_π_star: No description available.",        tex_label="\\sigma_{\\pi^*}")
    m <= parameter(:σ_lr,     0.1766, (1e-8,10.),      (1e-8, 5.),    DSGE.Exponential(), RootInverseGamma(2., 0.75),  fixed=false, description="σ_lr: No description available.",
                   tex_label="\\sigma_{lr}")
    m <= parameter(:σ_z_p,     0.1662, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false, description="σ_z_p: No description available.",            tex_label="\\sigma_{z^p}")
    m <= parameter(:σ_tfp,    0.9391, (1e-8, 5.),      (1e-8, 5.),    DSGE.Exponential(),   RootInverseGamma(2., 0.10),  fixed=false, description="σ_tfp: No description available.",           tex_label="\\sigma_{tfp}")
    m <= parameter(:σ_gdpdef, 0.1575, (1e-8, 5.), (1e-8, 5.),DSGE.Exponential(),
         RootInverseGamma(2., 0.10), fixed=false,
         description="σ_gdpdef: No description available.",
         tex_label="\\sigma_{gdpdef}")

    m <= parameter(:σ_corepce, 0.0999, (1e-8, 5.),(1e-8, 5.),DSGE.Exponential(),RootInverseGamma(2., 0.10),
                   fixed=false,
                   description="σ_corepce: No description available.",
                   tex_label="\\sigma_{corepce}")

    # standard deviations of the anticipated policy shocks
    for i = 1:n_anticipated_shocks_padding(m)
        if i < 13
            m <= parameter(symbol("σ_r_m$i"), .2, (1e-7, 100.), (1e-5, 0.), DSGE.Exponential(),
                           RootInverseGamma(4., .2), fixed=false,
                           description="σ_r_m$i: No description available.",
                           tex_label=@sprintf("\\sigma_{ant%d}",i))
        else
            m <= parameter(symbol("σ_r_m$i"), .0, (1e-7, 100.), (1e-5, 0.),
                           DSGE.Exponential(), RootInverseGamma(4., .2), fixed=true,
                           description="σ_r_m$i: No description available.",
                           tex_label=@sprintf("\\sigma_{ant%d}",i))
        end
    end

    m <= parameter(:η_gz,       0.8400, (1e-5, 0.999), (1e-5, 0.999), DSGE.SquareRoot(),
                   BetaAlt(0.50, 0.20), fixed=false,
                   description="η_gz: Correlate g and z shocks.",
                   tex_label="\\eta_{gz}")

    m <= parameter(:η_λ_f,      0.7892, (1e-5, 0.999), (1e-5, 0.999), DSGE.SquareRoot(),
                   BetaAlt(0.50, 0.20),         fixed=false,
                   description="η_λ_f: No description available.",
                   tex_label="\\eta_{\\lambda_f}")

    m <= parameter(:η_λ_w,      0.4226, (1e-5, 0.999), (1e-5, 0.999), DSGE.SquareRoot(),
                   BetaAlt(0.50, 0.20),         fixed=false,
                   description="η_λ_w: AR(2) coefficient on wage markup shock process.",
                   tex_label="\\eta_{\\lambda_w}")

    m <= parameter(:Iendoα, 0.0000, (0.000, 1.000), (0., 0.), DSGE.Untransformed(),
                   BetaAlt(0.50, 0.20), fixed=true,
                   description="Iendoα: Indicates whether to use the model's endogenous α in the capacity utilization adjustment of total factor productivity.",
                   tex_label="I\\{\\alpha^{model}\\}")

    m <= parameter(:Γ_gdpdef,  1.0354, (-10., 10.), (-10., -10.),  DSGE.Untransformed(),
                   Normal(1.00, 2.), fixed=false,
                   description="Γ_gdpdef: No description available.",
                   tex_label="\\Gamma_{gdpdef}")

    m <= parameter(:δ_gdpdef,   0.0181, (-9.1, 9.1), (-10., -10.),  DSGE.Untransformed(),
                   Normal(0.00, 2.),            fixed=false,
                   description="δ_gdpdef: No description available.",
                   tex_label="\\delta_{gdpdef}")

    # steady states
    m <= SteadyStateParameter(:z_star,  NaN, description="No description available.", tex_label="\\z_*")
    m <= SteadyStateParameter(:rstar,   NaN, description="No description available.", tex_label="\\r_*")
    m <= SteadyStateParameter(:Rstarn,  NaN, description="No description available.", tex_label="\\R_*_n")
    m <= SteadyStateParameter(:r_k_star,  NaN, description="No description available.", tex_label="\\r^k_*")
    m <= SteadyStateParameter(:wstar,   NaN, description="No description available.", tex_label="\\w_*")
    m <= SteadyStateParameter(:Lstar,   NaN, description="No description available.", tex_label="\\L_*")
    m <= SteadyStateParameter(:kstar,   NaN, description="Effective capital that households rent to firms in the steady state.", tex_label="\\k_*")
    m <= SteadyStateParameter(:kbarstar, NaN, description="Total capital owned by households in the steady state.", tex_label="\\bar{k}_*")
    m <= SteadyStateParameter(:istar,  NaN, description="Detrended steady-state investment", tex_label="\\i_*")
    m <= SteadyStateParameter(:ystar,  NaN, description="No description available.", tex_label="\\y_*")
    m <= SteadyStateParameter(:cstar,  NaN, description="No description available.", tex_label="\\c_*")
    m <= SteadyStateParameter(:wl_c,   NaN, description="No description available.", tex_label="\\wl_c")
    m <= SteadyStateParameter(:nstar,  NaN, description="No description available.", tex_label="\\n_*")
    m <= SteadyStateParameter(:vstar,  NaN, description="No description available.", tex_label="\\v_*")
    m <= SteadyStateParameter(:ζ_spσ_ω,  NaN, description="No description available.", tex_label="\\zeta_{sp_{\\sigma_\\omega}}")
    m <= SteadyStateParameter(:ζ_spμ_e,   NaN, description="No description available.", tex_label="\\zeta_{sp_{\\mu_e}}")
    m <= SteadyStateParameter(:ζ_nRk,     NaN, description="No description available.", tex_label="\\zeta_{n_R_k}")
    m <= SteadyStateParameter(:ζ_nR,      NaN, description="No description available.", tex_label="\\zeta_{n_R}")
    m <= SteadyStateParameter(:ζ_nqk,     NaN, description="No description available.", tex_label="\\zeta_{n_q_k}")
    m <= SteadyStateParameter(:ζ_nn,      NaN, description="No description available.", tex_label="\\zeta_{nn}")
    m <= SteadyStateParameter(:ζ_nμ_e,    NaN, description="No description available.", tex_label="\\zeta_{n_{\\mu_e}}")
    m <= SteadyStateParameter(:ζ_nσ_ω,   NaN, description="No description available.", tex_label="\\zeta_{n_{\\sigma_\\omega}}")

    init_model_indices!(m)
    init_subspec(m)
    steadystate!(m)
    return m
end

# functions that are used to compute financial frictions
# steady-state values from parameter values
@inline function ζ_spb_fn(z, σ, spr)
    zetaratio = ζ_bω_fn(z, σ, spr)/ζ_zω_fn(z, σ, spr)
    nk = nk_fn(z, σ, spr)
    return -zetaratio/(1-zetaratio)*nk/(1-nk)
end

@inline function ζ_bω_fn(z, σ, spr)
    nk          = nk_fn(z, σ, spr)
    μstar       = μ_fn(z, σ, spr)
    ω_star       = ω_fn(z, σ)
    Γstar       = Γ_fn(z, σ)
    Gstar       = G_fn(z, σ)
    dΓ_dω_star   = dΓ_dω_fn(z)
    dG_dω_star   = dG_dω_fn(z, σ)
    d2Γ_dω2star = d2Γ_dω2_fn(z, σ)
    d2G_dω2star = d2G_dω2_fn(z, σ)
    return ω_star*μstar*nk*(d2Γ_dω2star*dG_dω_star - d2G_dω2star*dΓ_dω_star)/
        (dΓ_dω_star - μstar*dG_dω_star)^2/spr/(1 - Γstar + dΓ_dω_star*(Γstar - μstar*Gstar)/
            (dΓ_dω_star - μstar*dG_dω_star))
end

@inline function ζ_zω_fn(z, σ, spr)
    μstar = μ_fn(z, σ, spr)
    return ω_fn(z, σ)*(dΓ_dω_fn(z) - μstar*dG_dω_fn(z, σ))/
        (Γ_fn(z, σ) - μstar*G_fn(z, σ))
end

nk_fn(z, σ, spr) = 1 - (Γ_fn(z, σ) - μ_fn(z, σ, spr)*G_fn(z, σ))*spr
μ_fn(z, σ, spr)  =
    (1 - 1/spr)/(dG_dω_fn(z, σ)/dΓ_dω_fn(z)*(1 - Γ_fn(z, σ)) + G_fn(z, σ))
ω_fn(z, σ)        = exp(σ*z - σ^2/2)
G_fn(z, σ)        = cdf(Normal(), z-σ)
Γ_fn(z, σ)        = ω_fn(z, σ)*(1 - cdf(Normal(), z)) + cdf(Normal(), z-σ)
dG_dω_fn(z, σ)    = pdf(Normal(), z)/σ
d2G_dω2_fn(z, σ)  = -z*pdf(Normal(), z)/ω_fn(z, σ)/σ^2
dΓ_dω_fn(z)       = 1 - cdf(Normal(), z)
d2Γ_dω2_fn(z, σ)  = -pdf(Normal(), z)/ω_fn(z, σ)/σ
dG_dσ_fn(z, σ)    = -z*pdf(Normal(), z-σ)/σ
d2G_dωdσ_fn(z, σ) = -pdf(Normal(), z)*(1 - z*(z-σ))/σ^2
dΓ_dσ_fn(z, σ)    = -pdf(Normal(), z-σ)
d2Γ_dωdσ_fn(z, σ) = (z/σ-1)*pdf(Normal(), z)

"""
```
steadystate!(m::Carvalho)
```

Calculates the model's steady-state values. `steadystate!(m)` must be called whenever
the parameters of `m` are updated.
"""
function steadystate!(m::Carvalho)
    SIGWSTAR_ZERO = 0.5

    m[:z_star]    = log(1+m[:γ]) + m[:α]/(1-m[:α])*log(m[:Upsilon])
    m[:rstar]    = exp(m[:σ_c]*m[:z_star]) / m[:β]
    m[:Rstarn]   = 100*(m[:rstar]*m[:π_star] - 1)
    m[:r_k_star]   = m[:spr]*m[:rstar]*m[:Upsilon] - (1-m[:δ])
    m[:wstar]    = (m[:α]^m[:α] * (1-m[:α])^(1-m[:α]) * m[:r_k_star]^(-m[:α]) / m[:Φ])^(1/(1-m[:α]))
    m[:Lstar]    = 1.
    m[:kstar]    = (m[:α]/(1-m[:α])) * m[:wstar] * m[:Lstar] / m[:r_k_star]
    m[:kbarstar] = m[:kstar] * (1+m[:γ]) * m[:Upsilon]^(1 / (1-m[:α]))
    m[:istar]    = m[:kbarstar] * (1-((1-m[:δ])/((1+m[:γ]) * m[:Upsilon]^(1/(1-m[:α])))))
    m[:ystar]    = (m[:kstar]^m[:α]) * (m[:Lstar]^(1-m[:α])) / m[:Φ]
    m[:cstar]    = (1-m[:g_star])*m[:ystar] - m[:istar]
    m[:wl_c]     = (m[:wstar]*m[:Lstar])/(m[:cstar]*m[:λ_w])

    # FINANCIAL FRICTIONS ADDITIONS
    # solve for σ_ω_star and zω_star
    zω_star = quantile(Normal(), m[:Fω].scaledvalue)
    σ_ω_star = SIGWSTAR_ZERO
    try
        σ_ω_star = fzero(sigma -> ζ_spb_fn(zω_star, sigma, m[:spr]) - m[:ζ_spb], 0.5)
    catch
        σ_ω_star = SIGWSTAR_ZERO
    end
    # evaluate ωbarstar
    ωbarstar = ω_fn(zω_star, σ_ω_star)

    # evaluate all BGG function elasticities
    Gstar                   = G_fn(zω_star, σ_ω_star)
    Γstar               = Γ_fn(zω_star, σ_ω_star)
    dGdω_star            = dG_dω_fn(zω_star, σ_ω_star)
    d2Gdω2star          = d2G_dω2_fn(zω_star, σ_ω_star)
    dΓdω_star        = dΓ_dω_fn(zω_star)
    d2Γdω2star      = d2Γ_dω2_fn(zω_star, σ_ω_star)
    dGdσstar            = dG_dσ_fn(zω_star, σ_ω_star)
    d2Gdωdσstar     = d2G_dωdσ_fn(zω_star, σ_ω_star)
    dΓdσstar        = dΓ_dσ_fn(zω_star, σ_ω_star)
    d2Γdωdσstar = d2Γ_dωdσ_fn(zω_star, σ_ω_star)

    # evaluate μ, nk, and Rhostar
    μ_estar       = μ_fn(zω_star, σ_ω_star, m[:spr])
    nkstar        = nk_fn(zω_star, σ_ω_star, m[:spr])
    Rhostar       = 1/nkstar - 1

    # evaluate wekstar and vkstar
    wekstar       = (1-m[:γ_star]/m[:β])*nkstar - m[:γ_star]/m[:β]*(m[:spr]*(1-μ_estar*Gstar) - 1)
    vkstar        = (nkstar-wekstar)/m[:γ_star]

    # evaluate nstar and vstar
    m[:nstar]       = nkstar*m[:kstar]
    m[:vstar]       = vkstar*m[:kstar]

    # a couple of combinations
    ΓμG      = Γstar - μ_estar*Gstar
    ΓμGprime = dΓdω_star - μ_estar*dGdω_star

    # elasticities wrt ωbar
    ζ_bw       = ζ_bω_fn(zω_star, σ_ω_star, m[:spr])
    ζ_zw       = ζ_zω_fn(zω_star, σ_ω_star, m[:spr])
    ζ_bw_zw    = ζ_bw/ζ_zw

    # elasticities wrt σ_ω
    ζ_bσ_ω      = σ_ω_star * (((1 - μ_estar*dGdσstar/dΓdσstar) /
        (1 - μ_estar*dGdω_star/dΓdω_star) - 1)*dΓdσstar*m[:spr] + μ_estar*nkstar*
            (dGdω_star*d2Γdωdσstar - dΓdω_star*d2Gdωdσstar)/ΓμGprime^2) /
                ((1 - Γstar)*m[:spr] + dΓdω_star/ΓμGprime*(1-nkstar))
    ζ_zσ_ω      = σ_ω_star * (dΓdσstar - μ_estar*dGdσstar) / ΓμG
    m[:ζ_spσ_ω] = (ζ_bw_zw*ζ_zσ_ω - ζ_bσ_ω) / (1-ζ_bw_zw)

    # elasticities wrt μ_e
    ζ_bμ_e      = μ_estar * (nkstar*dΓdω_star*dGdω_star/ΓμGprime+dΓdω_star*Gstar*m[:spr]) /
        ((1-Γstar)*ΓμGprime*m[:spr] + dΓdω_star*(1-nkstar))
    ζ_zμ_e      = -μ_estar*Gstar/ΓμG
    m[:ζ_spμ_e] = (ζ_bw_zw*ζ_zμ_e - ζ_bμ_e) / (1-ζ_bw_zw)

    # some ratios/elasticities
    Rkstar        = m[:spr]*m[:π_star]*m[:rstar] # (r_k_star+1-δ)/Upsilon*π_star
    ζ_gw       = dGdω_star/Gstar*ωbarstar
    ζ_Gσ_ω    = dGdσstar/Gstar*σ_ω_star

    # elasticities for the net worth evolution
    m[:ζ_nRk]    = m[:γ_star]*Rkstar/m[:π_star]/exp(m[:z_star])*(1+Rhostar)*(1 - μ_estar*Gstar*(1 - ζ_gw/ζ_zw))
    m[:ζ_nR]     = m[:γ_star]/m[:β]*(1+Rhostar)*(1 - nkstar + μ_estar*Gstar*m[:spr]*ζ_gw/ζ_zw)
    m[:ζ_nqk]    = m[:γ_star]*Rkstar/m[:π_star]/exp(m[:z_star])*(1+Rhostar)*(1 - μ_estar*Gstar*(1+ζ_gw/ζ_zw/Rhostar)) - m[:γ_star]/m[:β]*(1+Rhostar)
    m[:ζ_nn]     = m[:γ_star]/m[:β] + m[:γ_star]*Rkstar/m[:π_star]/exp(m[:z_star])*(1+Rhostar)*μ_estar*Gstar*ζ_gw/ζ_zw/Rhostar
    m[:ζ_nμ_e]   = m[:γ_star]*Rkstar/m[:π_star]/exp(m[:z_star])*(1+Rhostar)*μ_estar*Gstar*(1 - ζ_gw*ζ_zμ_e/ζ_zw)
    m[:ζ_nσ_ω]  = m[:γ_star]*Rkstar/m[:π_star]/exp(m[:z_star])*(1+Rhostar)*μ_estar*Gstar*(ζ_Gσ_ω-ζ_gw/ζ_zw*ζ_zσ_ω)

    return m
end

function settings_carvalho(m::Carvalho)

    # Anticipated shocks
    m <= Setting(:num_anticipated_shocks,         6, "Number of anticipated policy shocks")
    m <= Setting(:num_anticipated_shocks_padding, 20, "Padding for anticipated policy shocks")
    m <= Setting(:num_anticipated_lags,  24, "Number of periods back to incorporate zero bound expectations")

    return default_settings(m)
end
