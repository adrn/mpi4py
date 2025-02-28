cdef class Session:

    """
    Session
    """

    def __cinit__(self, Session session: Session | None = None):
        self.ob_mpi = MPI_SESSION_NULL
        cinit(self, session)

    def __dealloc__(self):
        dealloc(self)

    def __richcmp__(self, other, int op):
        if not isinstance(other, Session): return NotImplemented
        return richcmp(self, other, op)

    def __bool__(self) -> bool:
        return self.ob_mpi != MPI_SESSION_NULL

    def __reduce__(self) -> str | tuple[Any, ...]:
        return reduce_default(self)

    @classmethod
    def Init(
        cls,
        Info info: Info = INFO_NULL,
        Errhandler errhandler: Errhandler | None = None,
    ) -> Self:
        """
        Create a new session
        """
        cdef MPI_Errhandler cerrhdl = arg_Errhandler(errhandler)
        cdef Session session = <Session>New(cls)
        CHKERR( MPI_Session_init(
            info.ob_mpi, cerrhdl, &session.ob_mpi) )
        session_set_eh(session.ob_mpi)
        return session

    def Finalize(self) -> None:
        """
        Finalize a session
        """
        CHKERR( MPI_Session_finalize(&self.ob_mpi) )

    def Get_num_psets(self, Info info: Info = INFO_NULL) -> int:
        """
        Number of available process sets
        """
        cdef int num_psets = -1
        CHKERR( MPI_Session_get_num_psets(
            self.ob_mpi, info.ob_mpi, &num_psets) )
        return num_psets

    def Get_nth_pset(self, int n: int, Info info: Info = INFO_NULL) -> str:
        """
        Name of the nth process set
        """
        cdef int nlen = MPI_MAX_PSET_NAME_LEN
        cdef char *pset_name = NULL
        cdef tmp = allocate(nlen+1, sizeof(char), &pset_name)
        CHKERR( MPI_Session_get_nth_pset(
            self.ob_mpi, info.ob_mpi, n, &nlen, pset_name) )
        return mpistr(pset_name)

    def Get_info(self) -> Info:
        """
        Return the hints for a session
        """
        cdef Info info = <Info>New(Info)
        CHKERR( MPI_Session_get_info(
            self.ob_mpi, &info.ob_mpi) )
        return info

    def Get_pset_info(self, pset_name: str) -> Info:
        """
        Return the hints for a session and process set
        """
        cdef char *cname = NULL
        pset_name = asmpistr(pset_name, &cname)
        cdef Info info = <Info>New(Info)
        CHKERR( MPI_Session_get_pset_info(
            self.ob_mpi, cname, &info.ob_mpi) )
        return info

    def Create_group(self, pset_name: str) -> Group:
        """
        Create a new group from session and process set
        """
        cdef char *cname = NULL
        pset_name = asmpistr(pset_name, &cname)
        cdef Group group = <Group>New(Group)
        CHKERR( MPI_Group_from_session_pset(
            self.ob_mpi, cname, &group.ob_mpi) )
        return group

    # Error handling
    # --------------

    @classmethod
    def Create_errhandler(
        cls,
        errhandler_fn: Callable[[Session, int], None],
    ) -> Errhandler:
        """
        Create a new error handler for sessions
        """
        cdef Errhandler errhandler = <Errhandler>New(Errhandler)
        cdef MPI_Session_errhandler_function *fn = NULL
        cdef int index = errhdl_new(errhandler_fn, &fn)
        try: CHKERR( MPI_Session_create_errhandler(fn, &errhandler.ob_mpi) )
        except: errhdl_del(&index, fn); raise
        return errhandler

    def Get_errhandler(self) -> Errhandler:
        """
        Get the error handler for a session
        """
        cdef Errhandler errhandler = <Errhandler>New(Errhandler)
        CHKERR( MPI_Session_get_errhandler(self.ob_mpi, &errhandler.ob_mpi) )
        return errhandler

    def Set_errhandler(self, Errhandler errhandler: Errhandler) -> None:
        """
        Set the error handler for a session
        """
        CHKERR( MPI_Session_set_errhandler(self.ob_mpi, errhandler.ob_mpi) )

    def Call_errhandler(self, int errorcode: int) -> None:
        """
        Call the error handler installed on a session
        """
        CHKERR( MPI_Session_call_errhandler(self.ob_mpi, errorcode) )

    # Fortran Handle
    # --------------

    def py2f(self) -> int:
        """
        """
        return MPI_Session_c2f(self.ob_mpi)

    @classmethod
    def f2py(cls, arg: int) -> Session:
        """
        """
        return PyMPISession_New(MPI_Session_f2c(arg))


cdef Session __SESSION_NULL__ = def_Session( MPI_SESSION_NULL , "SESSION_NULL" )


# Predefined session handle
# -------------------------

SESSION_NULL  = __SESSION_NULL__  #: Null session handler
