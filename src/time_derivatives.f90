!Simple 4th-order centered time derivatives of pressure (5-point stencil).
!Output dpdt and d2pdt2 alongside the pressure snapshots, lagged by 2 snapshots.
module time_derivatives

  use decomp_2d_constants, only : mytype
  use decomp_2d,           only : xsize, fine_to_coarseV
  use decomp_2d_io,        only : decomp_2d_write_one

  implicit none
  private

  real(mytype), allocatable, save :: pbuf(:,:,:,:)
  integer,                   save :: itag(5) = -1
  integer,                   save :: nfilled = 0

  public :: tderiv_init, tderiv_finalise, tderiv_push_pressure

contains

  subroutine tderiv_init()
    if (.not. allocated(pbuf)) allocate(pbuf(xsize(1), xsize(2), xsize(3), 5))
    pbuf    = 0.0_mytype
    itag    = -1
    nfilled = 0
  end subroutine tderiv_init

  subroutine tderiv_finalise()
    if (allocated(pbuf)) deallocate(pbuf)
  end subroutine tderiv_finalise

  subroutine tderiv_push_pressure(p1, itime_now, dt_snap)

    use var,       only : uvisu, zero
    use utilities, only : gen_filename
    character(len=*), parameter :: io_name = "solution-io"

    real(mytype), intent(in) :: p1(xsize(1), xsize(2), xsize(3))
    integer,      intent(in) :: itime_now
    real(mytype), intent(in) :: dt_snap

    real(mytype), allocatable :: dpdt(:,:,:), d2pdt2(:,:,:)
    real(mytype) :: c1, c2
    integer :: tag

    pbuf(:,:,:,1) = pbuf(:,:,:,2)
    pbuf(:,:,:,2) = pbuf(:,:,:,3)
    pbuf(:,:,:,3) = pbuf(:,:,:,4)
    pbuf(:,:,:,4) = pbuf(:,:,:,5)
    pbuf(:,:,:,5) = p1

    itag(1) = itag(2); itag(2) = itag(3); itag(3) = itag(4); itag(4) = itag(5)
    itag(5) = itime_now

    if (nfilled < 5) nfilled = nfilled + 1
    if (nfilled < 5) return

    c1 = 1.0_mytype / (12.0_mytype * dt_snap)
    c2 = 1.0_mytype / (12.0_mytype * dt_snap * dt_snap)

    allocate(dpdt  (xsize(1), xsize(2), xsize(3)))
    allocate(d2pdt2(xsize(1), xsize(2), xsize(3)))

    dpdt   = c1 * ( -pbuf(:,:,:,5) + 8.0_mytype*pbuf(:,:,:,4) &
                  -  8.0_mytype*pbuf(:,:,:,2) + pbuf(:,:,:,1) )

    d2pdt2 = c2 * ( -pbuf(:,:,:,5) + 16.0_mytype*pbuf(:,:,:,4) &
                  -  30.0_mytype*pbuf(:,:,:,3)                  &
                  +  16.0_mytype*pbuf(:,:,:,2) -  pbuf(:,:,:,1) )

    tag = itag(3)

    uvisu = zero
    call fine_to_coarseV(1, dpdt, uvisu)
    call decomp_2d_write_one(1, uvisu, "data", &
         gen_filename(".", "dpdt", tag, 'bin'), 2, io_name, &
         opt_deferred_writes=.false.)

    uvisu = zero
    call fine_to_coarseV(1, d2pdt2, uvisu)
    call decomp_2d_write_one(1, uvisu, "data", &
         gen_filename(".", "d2pdt2", tag, 'bin'), 2, io_name, &
         opt_deferred_writes=.false.)

    deallocate(dpdt, d2pdt2)

  end subroutine tderiv_push_pressure

end module time_derivatives
