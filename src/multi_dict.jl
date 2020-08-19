#  multi-value dictionary (multidict)

import Base: haskey, get, get!, getkey, delete!, pop!, empty!,
             insert!, getindex, length, isempty, iterate,
             keys, values, copy, similar,  push!,
             count, size, eltype, empty

struct MultiDict{K,V}
    d::Dict{K,Vector{V}}

    MultiDict{K,V}() where {K,V} = new{K,V}(Dict{K,Vector{V}}())
    MultiDict{K,V}(d::Dict) where {K,V} = new{K,V}(d)
end

MultiDict{K,V}(pairs::Pair...) where {K,V} = MultiDict{K,V}(pairs)
function MultiDict{K,V}(kvs) where {K,V}
    md = MultiDict{K,V}()
    sizehint!(md.d, length(kvs))  # This might be an overestimate, but :shrug:
    for (k,v) in kvs
        insert!(md, k, v)
    end
    return md
end

MultiDict() = MultiDict{Any,Any}()
MultiDict(kv::Tuple{}) = MultiDict()
MultiDict(d::Dict{K,<:AbstractVector{V}}) where {K,V} = MultiDict{K,V}(d)
MultiDict(kvs) = multi_dict_with_eltype(kvs, eltype(kvs))

TP = Base.TP  # Tuple and/or Pair

#multi_dict_with_eltype(kvs, ::Type{Tuple{K,Vector{V}}}) where {K,V} = MultiDict{K,V}(kvs)
multi_dict_with_eltype(kvs, ::TP{K,V}) where {K,V} = MultiDict{K,V}(kvs)
multi_dict_with_eltype(kvs, t) = MultiDict{Any,Any}(kvs)
multi_dict_with_eltype(::TP{K,V}) where {K,V} = MultiDict{K,V}()
multi_dict_with_eltype(t) = MultiDict{Any,Any}()
#multi_dict_with_eltype(kv::Base.Generator, ::TP{K,V}) where {K,V} = MultiDict{K, V}(kv)
function multi_dict_with_eltype(kv::Base.Generator, t)
    T = Base.@default_eltype(kv)
    if T <: Union{Pair, Tuple{Any, Any}} && isconcretetype(T)
        return multi_dict_with_eltype(kv, T)
    end
    return Base.grow_to!(multi_dict_with_eltype(T), kv)
end

MultiDict(kv::AbstractArray{Pair{K,V}}) where {K,V}  = MultiDict(kv...)
MultiDict(ps::Pair{K,V}...) where {K,V}  = MultiDict{K,V}(ps)

# Copy constructors
MultiDict{K,V}(md::MultiDict) where {K,V} = MultiDict(md.d)
MultiDict(md::MultiDict) = MultiDict(md.d)


## Functions

## Most functions are simply delegated to the wrapped Dict

@delegate MultiDict.d [ haskey, get, get!, getkey,
                        getindex, length, isempty, eltype,
                        iterate, keys, values]

sizehint!(d::MultiDict, sz::Integer) = (sizehint!(d.d, sz); d)
copy(d::MultiDict) = MultiDict(d)
empty(d::MultiDict{K,V}) where {K,V} = MultiDict{K,V}()
empty(a::MultiDict, ::Type{K}, ::Type{V}) where {K, V} = MultiDict{K, V}()
==(d1::MultiDict, d2::MultiDict) = d1.d == d2.d
delete!(d::MultiDict, key) = (delete!(d.d, key); d)
empty!(d::MultiDict) = (empty!(d.d); d)

function insert!(d::MultiDict{K,V}, k, v) where {K,V}
    if !haskey(d.d, k)
        d.d[k] = V[]
    end
    push!(d.d[k], v)
    return d
end

function in(pr::(Tuple{Any,Any}), d::MultiDict{K,V}) where {K,V}
    k = convert(K, pr[1])
    v = get(d,k,Base.secret_table_token)
    (v !== Base.secret_table_token) && (pr[2] in v)
end

function pop!(d::MultiDict, key, default)
    vs = get(d, key, Base.secret_table_token)
    if vs === Base.secret_table_token
        if default !== Base.secret_table_token
            return default
        else
            throw(KeyError(key))
        end
    end
    v = pop!(vs)
    (length(vs) == 0) && delete!(d, key)
    return v
end
pop!(d::MultiDict, key) = pop!(d, key, Base.secret_table_token)

push!(d::MultiDict, kv::Pair) = insert!(d, kv[1], kv[2])
#push!(d::MultiDict, kv::Pair, kv2::Pair) = (push!(d.d, kv, kv2); d)
#push!(d::MultiDict, kv::Pair, kv2::Pair, kv3::Pair...) = (push!(d.d, kv, kv2, kv3...); d)

push!(d::MultiDict, kv) = insert!(d, kv[1], kv[2])
#push!(d::MultiDict, kv, kv2...) = (push!(d.d, kv, kv2...); d)

count(d::MultiDict) = length(keys(d)) == 0 ? 0 : mapreduce(k -> length(d[k]), +, keys(d))
size(d::MultiDict) = (length(keys(d)), count(d::MultiDict))

# enumerate

struct EnumerateAll
    d::MultiDict
end
enumerateall(d::MultiDict) = EnumerateAll(d)

length(e::EnumerateAll) = count(e.d)

function iterate(e::EnumerateAll)
    V = eltype(eltype(values(e.d)))
    vs = V[]
    dstate = iterate(e.d.d)
    vstate = iterate(vs)
    dstate === nothing || vstate === nothing && return nothing
    k = nothing
    while vstate === nothing
        ((k, vs), dst) = dstate
        dstate = iterate(e.d.d, dst)
        vstate = iterate(vs)
    end
    v, vst = vstate
    return ((k, v), (dstate, k, vs, vstate))
end

function iterate(e::EnumerateAll, s)
    dstate, k, vs, vstate = s
    dstate === nothing || vstate === nothing && return nothing
    while vstate === nothing
        ((k, vs), dst) = dstate
        dstate = iterate(e.d.d, dst)
        vstate = iterate(vs)
    end
    v, vst = vstate
    return ((k, v), (dstate, k, vs, vstate))
end

# grow_to! copied from Base -- needed for abstract generator constructor
function Base.grow_to!(dest::MultiDict{K, V}, itr) where V where K
    y = iterate(itr)
    y === nothing && return dest
    ((k,v), st) = y
    dest2 = empty(dest, typeof(k), typeof(v))
    insert!(dest2, k, v)
    Base.grow_to!(dest2, itr, st)
end

# this is a special case due to (1) allowing both Pairs and Tuples as elements,
# and (2) Pair being invariant. a bit annoying.
function Base.grow_to!(dest::MultiDict{K,V}, itr, st) where V where K
    y = iterate(itr, st)
    while y !== nothing
        (k,v), st = y
        if isa(k,K) && isa(v,V)
            insert!(dest, k, v)
        else
            new = empty(dest, promote_typejoin(K,typeof(k)), promote_typejoin(V,typeof(v)))
            merge!(new, dest)
            new[k] = v
            return grow_to!(new, itr, st)
        end
        y = iterate(itr, st)
    end
    return dest
end
