#------------------------------------------------------------------------------

cdef extern from "Python.h":
    ctypedef struct PyObject
    PyObject *Py_None
    void Py_CLEAR(PyObject*)

cdef extern from "Python.h":
    int PyIndex_Check(object)
    int PySlice_Check(object)
    int PySlice_GetIndicesEx(object, Py_ssize_t,
                             Py_ssize_t *, Py_ssize_t *,
                             Py_ssize_t *, Py_ssize_t *) except -1
    Py_ssize_t PyNumber_AsSsize_t(object, object) except? -1

#------------------------------------------------------------------------------

# Python 3 buffer interface (PEP 3118)
cdef extern from "Python.h":
    ctypedef struct Py_buffer:
        PyObject *obj
        void *buf
        Py_ssize_t len
        Py_ssize_t itemsize
        bint readonly
        char *format
        #int ndim
        #Py_ssize_t *shape
        #Py_ssize_t *strides
        #Py_ssize_t *suboffsets
    cdef enum:
        PyBUF_SIMPLE
        PyBUF_WRITABLE
        PyBUF_FORMAT
        PyBUF_ND
        PyBUF_STRIDES
        PyBUF_ANY_CONTIGUOUS
    int  PyObject_CheckBuffer(object)
    int  PyObject_GetBuffer(object, Py_buffer *, int) except -1
    void PyBuffer_Release(Py_buffer *)
    int  PyBuffer_FillInfo(Py_buffer *, object,
                           void *, Py_ssize_t,
                           bint, int) except -1

cdef extern from "Python.h":
    object PyLong_FromVoidPtr(void*)
    void*  PyLong_AsVoidPtr(object) except? NULL

cdef char BYTE_FMT[2]
BYTE_FMT[0] = c'B'
BYTE_FMT[1] = 0

#------------------------------------------------------------------------------

cdef inline int is_big_endian() noexcept nogil:
    cdef int i = 1
    return (<char*>&i)[0] == 0

cdef inline int is_little_endian() noexcept nogil:
    cdef int i = 1
    return (<char*>&i)[0] != 0

#------------------------------------------------------------------------------

include "asdlpack.pxi"
include "ascaibuf.pxi"

cdef int PyMPI_GetBuffer(object obj, Py_buffer *view, int flags) except -1:
    try:
        return PyObject_GetBuffer(obj, view, flags)
    except BaseException:
        try: return Py_GetDLPackBuffer(obj, view, flags)
        except NotImplementedError: pass
        except BaseException: raise
        try: return Py_GetCAIBuffer(obj, view, flags)
        except NotImplementedError: pass
        except BaseException: raise
        raise

#------------------------------------------------------------------------------

@cython.final
cdef class memory:

    """
    Memory buffer
    """

    cdef Py_buffer view

    def __cinit__(self, *args):
        if args:
            PyMPI_GetBuffer(args[0], &self.view, PyBUF_SIMPLE)
        else:
            PyBuffer_FillInfo(&self.view, <object>NULL,
                              NULL, 0, 0, PyBUF_SIMPLE)

    def __dealloc__(self):
        PyBuffer_Release(&self.view)

    @staticmethod
    def allocate(
        Aint nbytes: int,
        bint clear: bool = False,
    ) -> memory:
        """Memory allocation"""
        cdef void *buf = NULL
        cdef Py_ssize_t size = nbytes
        if size < 0:
            raise ValueError("expecting non-negative size")
        cdef object ob = rawalloc(size, 1, clear, &buf)
        cdef memory mem = <memory>New(memory)
        PyBuffer_FillInfo(&mem.view, ob, buf, size, 0, PyBUF_SIMPLE)
        return mem

    @staticmethod
    def frombuffer(
        obj: Buffer,
        bint readonly: bool = False,
    ) -> memory:
        """Memory from buffer-like object"""
        cdef int flags = PyBUF_SIMPLE
        if not readonly: flags |= PyBUF_WRITABLE
        cdef memory mem = <memory>New(memory)
        PyMPI_GetBuffer(obj, &mem.view, flags)
        mem.view.readonly = readonly
        return mem

    @staticmethod
    def fromaddress(
        address: int,
        Aint nbytes: int,
        bint readonly: bool = False,
    ) -> memory:
        """Memory from address and size in bytes"""
        cdef void *buf = PyLong_AsVoidPtr(address)
        cdef Py_ssize_t size = nbytes
        if size < 0:
            raise ValueError("expecting non-negative buffer length")
        elif size > 0 and buf == NULL:
            raise ValueError("expecting non-NULL address")
        cdef memory mem = <memory>New(memory)
        PyBuffer_FillInfo(&mem.view, <object>NULL,
                          buf, size, readonly, PyBUF_SIMPLE)
        return mem

    # properties

    property address:
        """Memory address"""
        def __get__(self) -> int:
            return PyLong_FromVoidPtr(self.view.buf)

    property obj:
        """The underlying object of the memory"""
        def __get__(self) -> Buffer | None:
            if self.view.obj == NULL: return None
            return <object>self.view.obj

    property nbytes:
        """Memory size (in bytes)"""
        def __get__(self) -> int:
            return self.view.len

    property readonly:
        """Boolean indicating whether the memory is read-only"""
        def __get__(self) -> bool:
            return self.view.readonly

    property format:
        """A string with the format of each element"""
        def __get__(self) -> str:
            if self.view.format != NULL:
                return pystr(self.view.format)
            return pystr(BYTE_FMT)

    property itemsize:
        """The size in bytes of each element"""
        def __get__(self) -> int:
            return self.view.itemsize

    # convenience methods

    def tobytes(self, order: str | None = None) -> bytes:
        """Return the data in the buffer as a byte string"""
        <void> order # unused
        return PyBytes_FromStringAndSize(<char*>self.view.buf, self.view.len)

    def toreadonly(self) -> memory:
        """Return a readonly version of the memory object"""
        cdef void *buf = self.view.buf
        cdef Py_ssize_t size = self.view.len
        cdef object obj = self
        if self.view.obj != NULL:
            obj = <object>self.view.obj
        cdef memory mem = <memory>New(memory)
        PyBuffer_FillInfo(&mem.view, obj,
                          buf, size, 1, PyBUF_SIMPLE)
        return mem

    def release(self) -> None:
        """Release the underlying buffer exposed by the memory object"""
        PyBuffer_Release(&self.view)
        PyBuffer_FillInfo(&self.view, <object>NULL,
                          NULL, 0, 0, PyBUF_SIMPLE)

    # buffer interface (PEP 3118)

    def __getbuffer__(self, Py_buffer *view, int flags):
        PyBuffer_FillInfo(view, self,
                          self.view.buf, self.view.len,
                          self.view.readonly, flags)

    # sequence interface (basic)

    def __len__(self):
        return self.view.len

    def __getitem__(self, object item):
        cdef Py_ssize_t start=0, stop=0, step=1, slen=0
        cdef unsigned char *buf = <unsigned char*>self.view.buf
        cdef Py_ssize_t blen = self.view.len
        if PyIndex_Check(item):
            start = PyNumber_AsSsize_t(item, IndexError)
            if start < 0: start += blen
            if start < 0 or start >= blen:
                raise IndexError("index out of range")
            return <long>buf[start]
        elif PySlice_Check(item):
            PySlice_GetIndicesEx(item, blen, &start, &stop, &step, &slen)
            if step != 1: raise IndexError("slice with step not supported")
            return tobuffer(self, buf+start, slen, self.view.readonly)
        else:
            raise TypeError("index must be integer or slice")

    def __setitem__(self, object item, object value):
        if self.view.readonly:
            raise TypeError("memory buffer is read-only")
        cdef Py_ssize_t start=0, stop=0, step=1, slen=0
        cdef unsigned char *buf = <unsigned char*>self.view.buf
        cdef Py_ssize_t blen = self.view.len
        cdef memory inmem
        if PyIndex_Check(item):
            start = PyNumber_AsSsize_t(item, IndexError)
            if start < 0: start += blen
            if start < 0 or start >= blen:
                raise IndexError("index out of range")
            buf[start] = <unsigned char>value
        elif PySlice_Check(item):
            PySlice_GetIndicesEx(item, blen, &start, &stop, &step, &slen)
            if step != 1: raise IndexError("slice with step not supported")
            if PyIndex_Check(value):
                <void>memset(buf+start, <unsigned char>value, <size_t>slen)
            else:
                inmem = getbuffer(value, 1, 0)
                if inmem.view.len != slen:
                    raise ValueError("slice length does not match buffer")
                <void>memmove(buf+start, inmem.view.buf, <size_t>slen)
        else:
            raise TypeError("index must be integer or slice")

#------------------------------------------------------------------------------

cdef inline memory newbuffer():
    return <memory>New(memory)

cdef inline memory getbuffer(object ob, bint readonly, bint format):
    cdef memory buf = newbuffer()
    cdef int flags = PyBUF_ANY_CONTIGUOUS
    if not readonly:
        flags |= PyBUF_WRITABLE
    if format:
        flags |= PyBUF_FORMAT
    PyMPI_GetBuffer(ob, &buf.view, flags)
    return buf

cdef inline memory asbuffer(object ob, void **base, MPI_Aint *size, bint ro):
    cdef memory buf
    if type(ob) is memory:
        buf = <memory> ob
        if buf.view.readonly and not ro:
            raise BufferError("Object is not writable")
    else:
        buf = getbuffer(ob, ro, 0)
    if base != NULL: base[0] = buf.view.buf
    if size != NULL: size[0] = buf.view.len
    return buf

cdef inline memory asbuffer_r(object ob, void **base, MPI_Aint *size):
    return asbuffer(ob, base, size, 1)

cdef inline memory asbuffer_w(object ob, void **base, MPI_Aint *size):
    return asbuffer(ob, base, size, 0)

cdef inline memory tobuffer(object ob, void *base, MPI_Aint size, bint ro):
    if size < 0:
        raise ValueError("expecting non-negative buffer length")
    cdef memory buf = newbuffer()
    PyBuffer_FillInfo(&buf.view, ob, base, size, ro, PyBUF_SIMPLE)
    return buf

cdef inline memory mpibuf(void *base, MPI_Count count):
    cdef MPI_Aint size = <MPI_Aint>count
    if count != <MPI_Count>size:
        raise OverflowError("integer {size} does not fit in 'MPI_Aint'")
    return tobuffer(<object>NULL, base, size, 0)

#------------------------------------------------------------------------------
