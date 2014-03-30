
# calculate crc checksums for data.  this process is closely related
# to the routines in IntModN (particularly GF2Poly), but the
# traditional implementations are optimized to the point where
# implementing them from "first principles" makes little sense
# (although we can use IntModN to check the results here).

# the basic idea is to do a polynomial division along the byte stream.
# it's all explained very nicely at
# http://en.wikipedia.org/wiki/Computation_of_cyclic_redundancy_checks

module CRC

export rem_no_table, make_table, rem_word_table, rem_small_table,
       rem_big_table

function check_generator{G<:Unsigned}(degree::Int, generator::G, chunk_size::Int)
    @assert degree <= 8 * sizeof(G) "generator too small for degree"
    # the shift needed to move something of chunk_size to the msb-1
    shift = degree - chunk_size
    @assert shift >= 0 "polynomial smaller than data chunk"
    # this is carry before shift, so is (implicit) msb / 2
    carry = one(G) << (degree - 1)
    rem_mask = convert(G, (1 << degree) - 1)
    (generator & rem_mask, shift, carry, rem_mask)
end


# basic calculation without a table

# we are careful to allow a missing msb in the generator, since that allows
# 8th degree polynomials to be specified in 8 bits, etc.

function rem_no_table{G<:Unsigned,D<:Unsigned}(degree::Int, generator::G, data::Vector{D})
    word_size = 8 * sizeof(D)
    generator, shift, carry, rem_mask = check_generator(degree, generator, word_size)
    remainder::G = zero(G)
    for word in data
        remainder = remainder $ (convert(G, word) << shift)
        for _ in 1:word_size
            if remainder & carry == carry
                remainder = (remainder << 1) $ generator
            else
                remainder <<= 1
            end
        end
    end
    # when the generator is smaller than the data type we don't lose
    # bits by overflow, so trim before returning
    remainder & rem_mask
end


# generate a lookup table of the requested size

function make_table{G<:Unsigned}(degree::Int, generator::G, table_size::Int)
    @assert table_size < 33 "table too large"  # even this is huge
    generator, shift, carry, rem_mask = check_generator(degree, generator, table_size)
    size = 2 ^ table_size
    table = Array(G, size)
    for word in 0:(size-1)
        remainder::G = convert(G, word << shift)
        for _ in 1:table_size
            if remainder & carry == carry
                remainder = (remainder << 1) $ generator
            else
                remainder = remainder << 1
            end
        end
        table[word+1] = remainder
    end
    table
end


# use a table that matches the size of the input data words.

function rem_word_table{G<:Unsigned,D<:Unsigned}(degree::Int, generator::G, data::Vector{D}, table::Vector{G})
    word_size = 8 * sizeof(D)
    @assert 2 ^ word_size == length(table) "wrong sized table"
    generator, shift, carry, rem_mask = check_generator(degree, generator, word_size)
    remainder::G = zero(G)
    for word in data
        remainder = remainder $ (convert(G, word) << shift)
        remainder = rem_mask & ((remainder << word_size) $ table[1 + (remainder >>> shift)])
    end
    remainder
end


# use a table that is smaller than the size of the input data words
# (for efficiency it must be an exact divisor).

function rem_small_table{G<:Unsigned,D<:Unsigned}(degree::Int, generator::G, data::Vector{D}, table::Vector{G})
    word_size = 8 * sizeof(D)
    block_size = iround(log2(length(table)))
    @assert word_size >= block_size "table too large for input words"
    @assert word_size % block_size == 0 "table block size is not an exact divisor of input word size"
    generator, word_shift, carry, rem_mask = check_generator(degree, generator, word_size)
    n_shifts = div(word_size, block_size)
    block_shift = degree - block_size
    block_mask = convert(G, (1 << block_size) - 1) << block_shift
    remainder::G = zero(G)
    for word in data
        tmp = convert(G, word) << word_shift
        for _ in 1:n_shifts
            remainder = remainder $ (tmp & block_mask)
            remainder = rem_mask & ((remainder << block_size) $ table[1 + (remainder >>> block_shift)])
            tmp <<= block_size
        end
    end
    remainder
end


# use a table that is larger than the size of the input data words
# (for efficiency it must be an exact multiple).

function rem_big_table{G<:Unsigned,D<:Unsigned}(degree::Int, generator::G, data::Vector{D}, table::Vector{G})
    word_size = 8 * sizeof(D)
    block_size = iround(log2(length(table)))
    @assert word_size <= block_size "table too small for input words"
    @assert block_size % word_size == 0 "table block size is not an exact multiple of input word size"
    @assert block_size <= degree "table block size is too large for polynomial degree"
    generator, word_shift, carry, rem_mask = check_generator(degree, generator, word_size)
    n_shifts = div(block_size, word_size)
    block_shift = degree - block_size
    remainder::G = zero(G)
    iter = start(data)
    left_shift, right_shift = block_size, block_shift
    while !done(data, iter)
        for i in 1:n_shifts
            if !done(data, iter)
                shift = word_shift - (i-1) * word_size
                word, iter = next(data, iter)
                remainder = remainder $ (convert(G, word) << shift)
            else
                left_shift -= word_size
                right_shift += word_size
            end
        end
        remainder = rem_mask & ((remainder << left_shift) $ table[1 + (remainder >>> right_shift)])
    end
    remainder
end


end
