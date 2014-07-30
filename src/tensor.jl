# tensor.jl
#
# Tensor provides a dense implementation of an AbstractTensor type without any
# symmetry assumptions, i.e. it describes tensors living in the full tensor
# product space of its index spaces.
#
# Written by Jutho Haegeman

#++++++++++++++
# Tensor type:
#++++++++++++++
# Type definition and constructors:
#-----------------------------------
type Tensor{S,T,N} <: AbstractTensor{S,T,N}
    data::Array{T,N}
    space::ProductSpace{N,S}
    function Tensor(data::Array{T},space::ProductSpace{N,S})
        if length(data)!=dim(space)
            throw(DimensionMismatch("data not of right size"))
        end
        return new(reshape(data,map(dim,space)),space)
    end
end

# Show method:
#-------------
function Base.show{S,T,N}(io::IO,t::Tensor{S,T,N})
    print(io," Tensor ∈ $T")
    for n=1:N
        print(io, n==1 ? "[" : " ⊗ ")
        showcompact(io,space(t,n))
    end
    println(io,"]:")
    Base.showarray(io,t.data;header=false)
end

# Basic methods for characterising a tensor:
#--------------------------------------------
space(t::Tensor,ind::Int)=t.space[ind]
space(t::Tensor)=t.space

# General constructors
#---------------------
# with data
tensor{T<:Real,N}(data::Array{T,N})=Tensor{CartesianSpace,T,N}(data,prod(CartesianSpace,size(data)))
function tensor{T,N}(data::Array{T,N})
    warning("for complex array, consider specifying Euclidean index spaces")
    Tensor{CartesianSpace,T,N}(data,map(CartesianSpace,size(data)))
end

tensor{S,T,N}(data::Array{T},P::ProductSpace{N,S})=Tensor{S,T,N}(data,P)

# without data
tensor{T}(::Type{T},P::ProductSpace)=tensor(Array(T,dim(P)),P)
tensor(P::ProductSpace)=tensor(Float64,P)

Base.similar{S,T,N}(t::Tensor{S},::Type{T},P::ProductSpace{N,S}=space(t))=tensor(similar(t.data,T,dim(P)),P)
Base.similar{S,N}(t::Tensor{S},P::ProductSpace{N,S}=space(t))=tensor(similar(t.data,dim(P)),P)

Base.zero(t::Tensor)=tensor(zero(t.data),space(t))

Base.zeros{T}(::Type{T},P::ProductSpace)=tensor(zeros(T,dim(P)),P)
Base.zeros(P::ProductSpace)=tensor(zeros(dim(P)),P)

Base.rand{T}(::Type{T},P::ProductSpace)=tensor(2*rand(T,dim(P))-1,P)
Base.rand(P::ProductSpace)=tensor(2*rand(dim(P))-1,P)

Base.eye{T}(::Type{T},V::IndexSpace)=tensor(eye(T,dim(V)),V'*V)
Base.eye(V::IndexSpace)=tensor(eye(dim(V)),V'*V)

# tensors from concatenation
function tensorcat{S}(catind, X::Tensor{S}...)
    catind = collect(catind)
    isempty(catind) && error("catind should not be empty")
    # length(unique(catdims)) != length(catdims) && error("every dimension should appear only once")

    nargs = length(X)
    numindX = map(numind, X)
    
    all(numindX.== numindX[1]) || throw(SpaceError("all tensors should have the same number of indices for concatenation"))
    
    numindC = numindX[1]
    ncatind = setdiff(1:numindC,catind)
    spaceCvec = Array(S, numindC)
    for n = 1:numindC
        spaceCvec[n] = space(X[1],n)
    end
    for i = 2:nargs
        for n in catind
            spaceCvec[n] = directsum(spaceCvec[n], space(X[i],n))
        end
        for n in ncatind
            spaceCvec[n] == space(X[i],n) || throw(SpaceError("space mismatch for index $n"))
        end
    end
    spaceC = prod(spaceCvec)
    typeC = mapreduce(eltype, promote_type, X)
    dataC = zeros(typeC, map(dim,spaceC))

    offset = zeros(Int,numindC)
    for i=1:nargs
        currentdims=ntuple(numindC,n->dim(space(X[i],n)))
        currentrange=[offset[n]+(1:currentdims[n]) for n=1:numindC]
        dataC[currentrange...] = X[i].data
        for n in catind
            offset[n]+=currentdims[n]
        end
    end
    return tensor(dataC,spaceC)
end

# Copy and fill tensors:
#------------------------
function Base.copy!(tdest::Tensor,tsource::Tensor)
    # Copies data of tensor tsource to tensor tdest if compatible
    if space(tdest)!=space(tsource)
        throw(SpaceError("tensor spaces don't match"))
    end
    copy!(tdest.data,tsource.data)
end
Base.fill!{S,T}(tdest::Tensor{S,T},value::Number)=fill!(tdest.data,convert(T,value))

# Vectorization:
#----------------
Base.vec(t::Tensor)=vec(t.data)
# Convert the non-trivial degrees of freedom in a tensor to a vector to be passed to eigensolvers etc.

# Conversion and promotion:
#---------------------------
Base.full(t::Tensor)=t.data

Base.promote_rule{S,T1,T2,N}(::Type{Tensor{S,T1,N}},::Type{Tensor{S,T2,N}})=Tensor{S,promote_type(T1,T2),N}
Base.convert{S,T1,T2,N}(::Type{Tensor{S,T1,N}},t::Tensor{S,T2,N})=tensor(convert(Array{T1,N},t.data),space(t))
Base.convert{S,T1,T2,N}(::Type{AbstractTensor{S,T1,N}},t::Tensor{S,T2,N})=tensor(convert(Array{T1,N},t.data),space(t))

Base.float{S,T<:FloatingPoint}(t::Tensor{S,T})=t
Base.float(t::Tensor)=tensor(float(t.data),space(t))

Base.real{S,T<:Real}(t::Tensor{S,T})=t
Base.real(t::Tensor)=tensor(real(t.data),space(t))
Base.complex{S,T<:Complex}(t::Tensor{S,T})=t
Base.complex(t::Tensor)=tensor(complex(t.data),space(t))

for (f,T) in ((:float32,    Float32),
              (:float64,    Float64),
              (:complex64,  Complex64),
              (:complex128, Complex128))
    @eval (Base.$f){S}(t::Tensor{S,$T}) = t
    @eval (Base.$f)(t::Tensor) = Tensor(($f)(t.data),space(t))
end

# Basic algebra:
#----------------
# hermitian conjugation inverts order of indices, is only way to make
# this compatible with tensors coupled to fermions
function Base.ctranspose(t::Tensor)
    tdest=similar(t,space(t)')
    return ctranspose!(tdest,tsource)
end

function ctranspose!(tdest::Tensor,tsource::Tensor)
    if space(tdest)!=space(tsource)'
        throw(SpaceError("tensor spaces don't match"))
    end
    N=numind(tsource)
    TensorOperations.tensorcopy!(tsource.data,1:N,tdest.data,N:-1:1)
    conj!(tdest.data)
    return tdest
end

Base.scale(t::Tensor,a::Number)=tensor(scale(t.data,a),space(t))
Base.scale!(t::Tensor,a::Number)=(scale!(t.data,convert(eltype(t),a));return t)

-(t::Tensor)=tensor(-t.data,space(t))

function +(t1::Tensor,t2::Tensor)
    if space(t1)!=space(t2)
        throw(SpaceError("tensor spaces do not agree"))
    end
    return tensor(t1.data+t2.data,space(t1))
end

function -(t1::Tensor,t2::Tensor)
    if space(t1)!=space(t2)
        throw(SpaceError("tensor spaces do not agree"))
    end
    return tensor(t1.data-t2.data,space(t1))
end

Base.vecnorm(t::Tensor)=vecnorm(t.data)
# Frobenius norm of tensor

# Indexing
#----------
# linear indexing using ProductBasisVector
Base.getindex{S,T,N}(t::Tensor{S,T,N},b::ProductBasisVector{N,S})=getindex(t.data,Base.to_index(b))
Base.setindex!{S,T,N}(t::Tensor{S,T,N},value,b::ProductBasisVector{N,S})=setindex!(t.data,value,Base.to_index(b))

# Tensor Operations
#-------------------
TensorOperations.scalar{S,T}(t::Tensor{S,T,0})=scalar(t.data)

function TensorOperations.tensorcopy!{S,T1,T2,N}(t1::Tensor{S,T1,N},labels1,t2::Tensor{S,T2,N},labels2)
    # Replaces tensor t2 with t1
    perm=indexin(labels1,labels2)

    length(perm) == N || throw(TensorOperations.LabelError("invalid label specification"))
    isperm(perm) || throw(TensorOperations.LabelError("invalid label specification"))
    for i = 1:N
        space(t1,i) == space(t2,perm[i]) || throw(SpaceError("incompatible index spaces of tensors"))
    end

    TensorOperations.tensorcopy!(t1.data,labels1,t2.data,labels2)
    return t2
end
function TensorOperations.tensoradd!{S,T1,T2,N}(alpha::Number,t1::Tensor{S,T1,N},labels1,beta::Number,t2::Tensor{S,T2,N},labels2)
    # Replaces tensor t2 with beta*t2+alpha*t1
    perm=indexin(labels1,labels2)

    length(perm) == N || throw(TensorOperations.LabelError("invalid label specification"))
    isperm(perm) || throw(TensorOperations.LabelError("invalid label specification"))
    for i = 1:N
        space(t1,i) == space(t2,perm[i]) || throw(SpaceError("incompatible index spaces of tensors"))
    end

    TensorOperations.tensoradd!(alpha,t1.data,labels1,beta,t2.data,labels2)
    return t2
end
function TensorOperations.tensortrace!{S,TA,NA,TC,NC}(alpha::Number,A::Tensor{S,TA,NA},labelsA,beta::Number,C::Tensor{S,TC,NC},labelsC)
    (length(labelsA)==NA && length(labelsC)==NC) || throw(LabelError("invalid label specification"))
    NA==NC && return tensoradd!(alpha,A,labelsA,beta,C,labelsC) # nothing to trace
    
    po=indexin(labelsC,labelsA)
    clabels=unique(setdiff(labelsA,labelsC))
    NA==NC+2*length(clabels) || throw(LabelError("invalid label specification"))
    
    pc1=Array(Int,length(clabels))
    pc2=Array(Int,length(clabels))
    for i=1:length(clabels)
        pc1[i]=findfirst(labelsA,clabels[i])
        pc2[i]=findnext(labelsA,clabels[i],pc1[i]+1)
    end
    isperm(vcat(po,pc1,pc2)) || throw(LabelError("invalid label specification"))
    
    for i = 1:NC
        space(A,po[i]) == space(C,i) || throw(SpaceError("space mismatch"))
    end
    for i = 1:div(NA-NC,2)
        space(A,pc1[i]) == dual(space(A,pc2[i])) || throw(SpaceError("space mismatch"))
    end
    
    tensortrace!(alpha,A.data,labelsA,beta,C.data,labelsC)
end
function TensorOperations.tensorcontract!{S}(alpha::Number,A::Tensor{S},labelsA,conjA::Char,B::Tensor{S},labelsB,conjB::Char,beta::Number,C::Tensor{S},labelsC;method=:BLAS)
    # Get properties of input arrays
    NA=numind(A)
    NB=numind(B)
    NC=numind(C)

    # Process labels, do some error checking and analyse problem structure
    if NA!=length(labelsA) || NB!=length(labelsB) || NC!=length(labelsC)
        throw(TensorOperations.LabelError("invalid label specification"))
    end
    ulabelsA=unique(labelsA)
    ulabelsB=unique(labelsB)
    ulabelsC=unique(labelsC)
    if NA!=length(ulabelsA) || NB!=length(ulabelsB) || NC!=length(ulabelsC)
        throw(TensorOperations.LabelError("tensorcontract requires unique label for every index of the tensor, handle inner contraction first with tensortrace"))
    end

    clabels=intersect(ulabelsA,ulabelsB)
    numcontract=length(clabels)
    olabelsA=intersect(ulabelsA,ulabelsC)
    numopenA=length(olabelsA)
    olabelsB=intersect(ulabelsB,ulabelsC)
    numopenB=length(olabelsB)

    if numcontract+numopenA!=NA || numcontract+numopenB!=NB || numopenA+numopenB!=NC
        throw(LabelError("invalid contraction pattern"))
    end

    # Compute and contraction indices and check size compatibility
    cindA=indexin(clabels,ulabelsA)
    oindA=indexin(olabelsA,ulabelsA)
    oindCA=indexin(olabelsA,ulabelsC)
    cindB=indexin(clabels,ulabelsB)
    oindB=indexin(olabelsB,ulabelsB)
    oindCB=indexin(olabelsB,ulabelsC)

    # check size compatibility
    spaceA=space(A)
    spaceB=space(B)
    spaceC=space(C)

    cspaceA=spaceA[cindA]
    cspaceB=spaceB[cindB]
    ospaceA=spaceA[oindA]
    ospaceB=spaceB[oindB]

    conjA=='C' || conjA=='N' || throw(ArgumentError("conjA should be 'C' or 'N'."))
    conjB=='C' || conjA=='N' || throw(ArgumentError("conjB should be 'C' or 'N'."))

    for i=1:numcontract
        cspaceA[i]==(conjA==conjB ? dual(cspaceB[i]) : cspaceB[i]) || throw(SpaceError("incompatible index space for label $(clabels[i])"))
    end
    for i=1:numopenA
        spaceC[oindCA[i]]==(conjA ? dual(ospaceA[i]) : ospaceA[i]) || throw(SpaceError("incompatible index space for label $(olabelsA[i])"))
    end
    for i=1:numopenB
        spaceC[oindCB[i]]==(conjB ? dual(ospaceB[i]) : ospaceB[i]) || throw(SpaceError("incompatible index space for label $(olabelsB[i])"))
    end

    TensorOperations.tensorcontract!(alpha,A.data,labelsA,conjA,B.data,labelsB,conjB,beta,C.data,labelsC;method=method)
    return C
end

# Methods below are only implemented for Cartesian or Euclidean tensors:
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
typealias EuclideanTensor{T,N} Tensor{EuclideanSpace,T,N}
typealias CartesianTensor{T,N} Tensor{CartesianSpace,T,N}

# Index methods
#---------------
for (S,TT) in ((CartesianSpace,CartesianTensor),(EuclideanSpace,EuclideanTensor))
    @eval function insertind(t::$TT,ind::Int,V::$S)
        N=numind(t)
        0<=ind<=N || throw(IndexError("index out of range"))
        iscnumber(V) || throw(SpaceError("can only insert index with c-number index space"))
        spacet=space(t)
        newspace=spacet[1:ind]*V*spacet[ind+1:N]
        return tensor(t.data,newspace)
    end
    @eval function deleteind(t::$TT,ind::$S)
        1<=ind<=numind(t) || throw(IndexError("index out of range"))
        iscnumber(space(t,ind)) || throw(SpaceError("can only squeeze index with c-number index space"))
        spacet=space(t)
        newspace=spacet[1:ind-1]*spacet[ind+1:N]
        return tensor(t.data,newspace)
    end
    @eval function fuseind(t::$TT,ind1::Int,ind2::Int,V::$S)
        N=numind(t)
        ind2==ind1+1 || throw(IndexError("only neighbouring indices can be fused"))
        1<=ind1<=N-1 || throw(IndexError("index out of range"))
        fuse(space(t,ind1),space(t,ind2),V) || throw(SpaceError("index spaces $(space(t,ind1)) and $(space(t,ind2)) cannot be fused to $V"))
        spacet=space(t)
        newspace=spacet[1:ind1-1]*V*spacet[ind2+1:N]
        return tensor(t.data,newspace)
    end
    @eval function splitind(t::$TT,ind::Int,V1::$S,V2::$S)
        1<=ind<=numind(t) || throw(IndexError("index out of range"))
        fuse(V1,V2,space(t,ind)) || throw(SpaceError("index space $(space(t,ind)) cannot be split into $V1 and $V2"))
        spacet=space(t)
        newspace=spacet[1:ind-1]*V1*V2*spacet[ind+1:N]
        return tensor(t.data,newspace)
    end
end

# Factorizations:
#-----------------
for (S,TT) in ((CartesianSpace,CartesianTensor),(EuclideanSpace,EuclideanTensor))
    @eval function Base.svd(t::$TT,leftind,rightind=setdiff(1:numind(t),leftind))
        # Perform singular value decomposition corresponding to bipartion of the
        # tensor indices into leftind and rightind.
        N=numind(t)
        spacet=space(t)
        p=vcat(leftind,rightind)
        if !isperm(p)
            throw(IndexError("Not a valid bipartation of the tensor indices"))
        end
        data=permutedims(t.data,p)
        # always copies data, also for trivial permutation
        leftspace=spacet[leftind]
        rightspace=spacet[rightind]
        leftdim=dim(leftspace)
        rightdim=dim(rightspace)
        data=reshape(data,(leftdim,rightdim))
        F=svdfact!(data)
        # overwrite, since data is already a copy anyway
        newdim=length(F[:S])
        newspace=$S(newdim)
        U=tensor(F[:U],leftspace*newspace')
        Sigma=tensor(diagm(F[:S]),newspace*newspace')
        V=tensor(F[:Vt],newspace*rightspace)
        return U,Sigma,V
    end

    @eval function svdtrunc(t::$TT,leftind=codomainind(t),rightind=setdiff(1:numind(t),leftind);truncdim::Int=dim(space(t)[leftind]),trunctol::Real=eps(abs(one(eltype(t)))))
        # Truncate tensor rank corresponding to bipartition into leftind and
        # rightind, based on singular value decomposition. Truncation parameters
        # are given as  keyword arguments: trunctol should always be one of the
        # possible arguments for specifying truncation, but truncdim can be
        # replaced with different parameters for other types of tensors.

        N=numind(t)
        spacet=space(t)
        p=vcat(leftind,rightind)
        if !isperm(p)
            throw(IndexError("Not a valid bipartation of the tensor indices"))
        end
        data=permutedims(t.data,p)
        # always copies data, also for trivial permutation
        leftspace=spacet[leftind]
        rightspace=spacet[rightind]
        leftdim=dim(leftspace)
        rightdim=dim(rightspace)
        data=reshape(data,(leftdim,rightdim))
        F=svdfact!(data)

        # find truncdim based on trunctolinfo
        sing=F[:S]
        normsing=norm(sing)
        trunctoldim=0
        while norm(sing[(trunctoldim+1):end])>trunctol*normsing
            trunctoldim+=1
            if trunctoldim==length(sing)
                break
            end
        end

        # choose minimal truncdim
        truncdim=min(truncdim,trunctoldim)
        truncerr=zero(eltype(sing))
        newspace=$S(truncdim)
        if truncdim<length(sing)
            truncerr=vecnorm(sing[(truncdim+1):end])
            Sigma=Sigma[1:truncdim]
            U=tensor(F[:U][:,1:truncdim],leftspace*newspace')
            Sigma=tensor(diagm(sing[1:truncdim]),newspace*newspace')
            V=tensor(F[:Vt][1:truncdim,:],newspace*rightspace)
        else
            U=tensor(F[:U],leftspace*newspace')
            Sigma=tensor(diagm(sing),newspace*newspace')
            V=tensor(F[:Vt],newspace*rightspace)
        end

        return U,Sigma,V,truncerr
    end

    @eval function leftorth(t::$TT,leftind,rightind=setdiff(1:numind(t),leftind))
        # Create orthogonal basis U for left indices, and remainder R for right
        # indices. Decomposition should be unique, such that it always returns the
        # same result for the same input tensor t. QR is fastest but only unique
        # after correcting for phases.
        N=numind(t)
        spacet=space(t)
        p=vcat(leftind,rightind)
        if !isperm(p)
            throw(IndexError("Not a valid bipartation of the tensor indices"))
        end
        data=permutedims(t.data,p)
        # always copies data, also for trivial permutation
        leftspace=spacet[leftind]
        rightspace=spacet[rightind]
        leftdim=dim(leftspace)
        rightdim=dim(rightspace)
        data=reshape(data,(leftdim,rightdim))
        if leftdim>rightdim
            F=qrfact!(data)
            newdim=rightdim

            # make unique by correcting for phase arbitrariness
            R=full(F[:R])
            phase=zeros(eltype(R),(newdim,))
            for i=1:newdim
                phase[i]=abs(R[i,i])/R[i,i]
            end
            R=scale!(phase,R)

            # also build unitary transformation
            U=full(F[:Q])
            U=scale(U,one(eltype(U))./phase)
        else
            newdim=leftdim
            R=data
            U=eye(eltype(data),newdim)
        end
        newspace=$S(newspace)
        return tensor(U,leftspace*newspace'), tensor(R,newspace*rightspace)
    end

    @eval function rightorth(t::$TT,leftind,rightind=setdiff(1:numind(t),leftind))
        # Create orthogonal basis U for right indices, and remainder R for left
        # indices. Decomposition should be unique, such that it always returns the
        # same result for the same input tensor t. QR of transpose fastest but only
        # unique after correcting for phases.
        N=numind(t)
        spacet=space(t)
        p=vcat(rightind,leftind)
        if !isperm(p)
            throw(IndexError("Not a valid bipartation of the tensor indices"))
        end
        data=permutedims(t.data,p)
        # always copies data, also for trivial permutation
        leftspace=spacet[leftind]
        rightspace=spacet[rightind]
        leftdim=dim(leftspace)
        rightdim=dim(rightspace)
        data=reshape(data,(rightdim,leftdim)) # data is already transposed by permutedims
        if leftdim<rightdim
            F=qrfact!(data)
            newdim=leftdim

            # make unique by correcting for phase arbitrariness
            R=full(F[:R])
            phase=zeros(eltype(R),(newdim,))
            for i=1:newdim
                phase[i]=abs(R[i,i])/R[i,i]
            end
            R=scale!(phase,R)

            U=full(F[:Q])
            U=scale(U,one(eltype(U))./phase)
        else
            newdim=rightdim
            R=data
            U=eye(eltype(data),newdim)
        end
        newspace=$S(newdim)
        return tensor(transpose(R),leftspace*newspace'), tensor(transpose(U),newspace*rightspace)
    end
end

# Methods below are only implemented for Cartesian or Euclidean matrices:
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
typealias EuclideanMatrix{T} EuclideanTensor{T,2}
typealias CartesianMatrix{T} CartesianTensor{T,2}

function Base.pinv(t::Union(EuclideanMatrix,CartesianMatrix))
    # Compute pseudo-inverse corresponding to bipartion of the tensor indices
    # into leftind and rightind.
    spacet=space(t)
    data=copy(t.data)
    leftdim=dim(spacet[1])
    rightdim=dim(spacet[2])

    F=svdfact!(data)
    Sinv=F[:S]
    for k=1:length(Sinv)
        if Sinv[k]>eps(Sinv[1])*max(leftdim,rightdim)
            Sinv[k]=one(Sinv[k])/Sinv[k]
        end
    end
    data=F[:V]*scale(F[:S],F[:U]')
    return tensor(data,spacet')
end

function Base.eig(t::Union(EuclideanMatrix,CartesianMatrix))
    # Compute eigenvalue decomposition.
    spacet=space(t)
    spacet[1] == spacet[2]' || throw(SpaceError("eigenvalue factorization only exists if left and right index space are dual"))
    data=copy(t.data)

    F=eigfact!(data)

    Lambda=tensor(diagm(F[:values]),spacet)
    V=tensor(F[:vectors],spacet)
    return Lambda, V
end

function Base.inv(t::Union(EuclideanMatrix,CartesianMatrix))
    # Compute inverse.
    spacet=space(t)
    spacet[1] == spacet[2]' || throw(SpaceError("inverse only exists if left and right index space are dual"))
    
    return tensor(inv(t.data),spacet)
end