!=================================================================================
! Simple Example: Strang Splitting of Adv-Diff Equation:  
!           phi_t + (u*phi - D*phi_x)_x = 0 (1D)
!           phi(0) = phi_0                  (IC)
!
! IC can be chosen via "inittype"	: 1-Gaussian, 2-Wave Packet, 3-Square Wave
! Reconstruction Type "recontype"	: 1-Gudonov,  2-PLM
!												  |
!         										  +--> Limiter: 1-MC, 2-SuperBee,
!																3-TVD
! Time Step "dttype" : 1-RK2 , 2-Midpoint, 3-Heun's
!=================================================================================

program OperatorSplitting_Simple

	implicit none
	
	!=============================================================================
	! Parameters
	!=============================================================================

	! TODO: Read Parameters from file
	! amount of cells and amount of ghost cells
	integer, parameter :: ncells 	= 64
	integer, parameter :: ngcells 	= 1

	! domain size
	double precision, parameter :: xmin = 0.d0
	double precision, parameter :: xmax = 1.d0

	! advection velocity
	double precision, parameter :: u = 1.d0

	! courant number cn = (u * dt / dx)
	double precision, parameter :: cn = 0.8d0

	! initial condition type
	integer, parameter :: inittype = 1

	! reconstruction type
	integer, parameter :: recontype = 1

	! if recontype == 2 --> PLM, choose slope limiter
	integer, parameter :: limiter = 1

	! time integration type
	integer, parameter :: dttype = 1
	
	! maximum simulation time
	double precision, parameter :: tmax = 5.d0

	
	double precision, dimension(2*ngcells + ncells) :: grid
	double precision, dimension(2*ngcells + ncells) :: phi, phi_left, phi_right, flux
	double precision, dimension(2*ngcells + ncells) :: phi_init

	double precision :: dx, dt

	! global parameters
	double precision, save :: t
	  

	!=============================================================================
	! Program
	!=============================================================================

	! setup grid and initial conditions
	call setup_grid(ncells, ngcells, xmin, xmax, dx, grid)
	call init(ncells, ngcells, inittype, grid, phi)
	
	phi_init = phi

	t = 0.d0
	
	! write out initial state
	call write_out(args...)

	do while (t < tmax)
		
		! handle ghost cells
		call update_gcells(ncells, ngcells, phi)
		
		! calculate new time step
		call calc_dt             	
		if (t + dt > tmax) then  
			dt = tmax - t        
		end if

		! reconstruct phi
		call reconstruct(ncells, ngcells, dx, dt, u, recontype, limiter, phi, 		&
																phi_left, phi_right)

		! strang splitting: 
		! 	-> solve advection equation for dt/2 				--> phi* 
		!	-> solve diffusion equation for dt using phi*		--> phi**
		!	-> solve advection equation for dt/2 using phi**	--> phi(t+dt)
		call solve_advection()
		


		! update time
		t = t + dt
	end do 	
end program


!=================================================================================  
! Subroutines
!=================================================================================

!-------------------------+
! output: writes out data |
!-------------------------+
subroutine output(ncells, ngcells, inittype, recontype, limiter, dttype , u, t,
 																grid, phi, folder)
	
	implicit none

	integer, intent(in) :: ncells, ngcells
	integer, intent(in) :: inittype, recontype, limiter, dttype
	
	double precision, intent(in) :: u, t
	
	double precision, dimension(2*ngcells+ncells), intent(in) :: grid, phi

	character(len=40), optional, intent(in) :: folder
	
	character(len=50) :: pre_string
	character(len=4)  :: time_string
	character(len=16) :: recon, init, res, tint

	integer :: i, imin, imax

	imin = ngcells + 1
	imax = ngcells + ncells

	! generate recon, init strings
	if (recontype == 1) then
		recon = "godunov"
	else if (recontype == 2) then 
		if (limiter == 1) then
			recon = "plm+MC"
		else if (limiter == 2) then
			recon = "plm+SBee"
		else if (limiter == 3) then
			recon = "plm+TVD"
		end if
	end if

	if (inittype == 1) then
		init = "gaussian"
	else if (inittype == 2) then
		init = "packet"
	else if (inittype == 3) then
		init = "square"
	end if

	if (dttype == 1) then
		tint = "RK2"
	else if (dttype == 2) then
		tint = "MP"
	else if (dttype == 3) then
		tint = "HEUN"
	end if

	! open output file
	write(time_string, '(f4.2)') t
	write(res, '(i8)') ncells
	
	if (present(folder)) then
		pre_string="AdvDiff"//trim(folder)
	else
		pre_string="AdvDiff"
	end if

	open(unit=20, filename = pre_string//"-Strang-"//trim(recon)//"-"//			&
							 trim(ttype)//"+CN-"//trim(init)//"-ncells="//		&
							 trim(adjustl(res))//"-t="//time_string, 			&
							 status="unknown")

	do i = imin, imax
		write(20, *) grid(i), phi(i)
	end do 

end subroutine output



!------------------------------+
! setup_grid: creates the grid |
!------------------------------+
subroutine setup_grid(ncells, ngcells, xmin, xmax, dx, grid)

	implicit none
		
	! amount of cells / ghost cells
	integer, intent(in) :: ncells, ngcells
		
	! maximum / minimum x value, x-step, grid array 
	double precision, intent(in) :: xmin, xmax
	double precision, intent(inout) :: dx 
	double precision, dimension(2*ngcells + ncells), intent(inout) :: grid

	! dummy index
	integer :: i 

	! create the grid
	dx = (xmax - xmin)/dble(ncells)

	do i = 1, 2*ngcells+ncells
		x(i) = (i - 0.5d0)*dx + xmin
	end do

	return
end subroutine setup_grid

!----------------------------------+
! init: set the initial conditions |
!----------------------------------+
subroutine init(ncells, ngcells, inittype, grid, phi)

	implicit none
		
	! number of cells / ghost cells
	integer, intent(in) :: ncells, ngcells

	! initialization type: 	1 -> Gaussian, 
	! 					   	2 -> Wave Paket
	integer, intent(in) :: inittype

	! grid, physical quantity phi
	double precision, dimension(2*ngcells+ncells), intent(in)		:: grid
	double precision, dimension(2*ngcells+ncells), intent(inout) 	:: phi

	! defining pi
	double precision, parameter :: pi = 4.d0*datan(1.d0)
		
	integer :: i, imin, imax
	
	imin = ngcells + 1
	imax = ngcells + ncells 		

	! loop over all cells and set initial conditions at the cell centre

	
	! TODO: Check +- 0.5d0 generic?
	if (inittype == 1) then
	! gaussian
		do i = imin, imax
			phi(i) = exp(-(x(i)- 0.5d0)**2/0.1d0**2)
		end do

	else if(inittype == 2) then
	! wave paket
		do i = imin, imax
			phi(i) = sin(16.d0*pi*x(i))*exp(-36.d0*(x(i)-0.5d0)**2)
		end do

	else if(inittype == 3) then
	! square wave
		if (x(i) > 0.333d0 .and. x(i) < 0.666d0) then
			phi(i) = 1.d0
		else
			phi(i) = 0.d0
		end if

	end if 
				
	return
end subroutine init


!------------------------------------+
! update_gcells: updates ghost cells |
!------------------------------------+
subroutine update_gcells(ncells, ngcells, phi)

	implicit none

	integer, intent(in) :: ncells, ngcells	
	double precision, intent(inout) :: phi

	integer :: i, imax
	imax = ngcells + ncells

	! left boundary
	do i = 1, ngcells 
		phi(i) = phi(ncells+i)
	end do

	! right boundary
	do i = imax+1, 2*ngcells+ncells  
		phi(i) = phi(i-imax+ng)
	end do

	return
end subroutine update_gcells

!----------------------------------- +
! calc_dt: computes the new timestep |	
!------------------------------------+	
subroutine calc_dt(dx, u, cn, dt)

	implicit none

	double precision, intent(in) :: dx
	double precision, intent(in) :: u
	double precision, intent(in) :: cn
	double precision, intent(inout) :: dt
	
	! due to stability constrains
	dt = cn*dx/abs(u)

end subroutine calc_dt


!---------------------------------------------+
! reconstruct: computes the interfaces states |
!---------------------------------------------+
subroutine reconstruct(ncells, ngcells, dx, dt, u, recontype, limiter, &
		                                			& phi, phi_left, phi_right)

	implicit none

	integer, intent(in) :: ncells, ngcells
	integer, intent(in) :: recontype, limiter

	double precision, intent(in) :: dx, dt, u
	
	double precision, dimension(2*ngcells+ncells), intent(in) :: phi
	double precision, dimension(2*ngcells+ncells), intent(inout):: phi_left, phi_right

	double precision, dimension(2*ngcells+ncells) :: slope

	integer :: i, imin, imax

	imin = ngcells + 1
	imax = ngcells + ncells

	if (recontype == 1) then
		
		! Godunov's method (piecewise constant)
		
		! for each interface, we want to construct the left and the right 
		! states. Here, i referes to the left edge of zone i 

		! interfaces imin to imax+1 affect the data in cells [imin, imax]	
		do i = imin, imax+1
			! the left state on the current interface comes from cell i-1
			phi_left(i) = phi(i-1) 

			! the right state on the current interface comes from cell i 
			phi_right(i) = phi(i)
		end do
	
	else if (recontype == 2) then

		! PLM with MC limiter (Monotonized Central)
		if (limiter == 1) then

			! interface states are found by Taylor expansionin time (trough dt/2)
			! and space (dx/2 towards the interface).

			! for each interface left and right states have be reconstructed.
			! Here, interface i refers to the left edge of zone i.
		
			do i = imin-1, imax+1

				slope(i) = 	minmod( 											&
								minmod(	2.d0*( phi(i)   - phi(i-1) )/dx,   		&
										2.d0*( phi(i+1) - phi(i)   )/dx ),		&
								0.5d0*( phi(i+1) - phi(i-1) )/dx   				&
							) 															   
			end do
		
		! PLM with SuperBee limiter
		else if (limiter == 2) then
			
			double precision :: slope1, slope2

			do i = imin-1, imax+1
				slope1 = minmod( (u(i+1) - u(i))/dx  , 2.d0*(u(i) - u(i-1))/dx )
				slope2 = minmod( 2.d0*(u(i+1) - u(i))/dx ,  (u(i) - u(i-1))/dx )

				slope(i) = maxmod(slope1, slope2)
			end do
		
		! PLM with TVD limiter (Total Variation Diminishing)
		else if (limiter == 3) then

			do i = imin-1, imax+1
				! called dx*u in paper
				slope(i) = max( ((phi(i+1) - phi(i)) * (phi(i) - phi(i-1)), 0) /&
																(phi(i+1) - phi(i-1))
			end do 
		end if

		if (limiter == 1 .or. limiter == 2) then)
			! interfaces imin to imax+1 affect the data in cells [imin, imax]
			do i = imin, imax+1
		
 				! the left state on the current interface comes from cell i-1
				phi_left(i)  = phi(i-1) + 0.5d0*dx*(1.d0 - u*(dt/dx))*slope(i-1)

				! the right state on the current interface comes from cell i 
				phi_right(i) = phi(i)   + 0.5d0*dx*(1.d0 + u*(dt/dx))*slope(i) 
			end do
		
		else if (limiter == 3) then
			do i = imin, imax+1
				phi_left(i)  = phi(i) - slope(i)
				phi_right(i) = phi(i) + slope(i)
 			end do
		end if
	
	end if  

	return
end subroutine reconstruct


!----------------------------------------------------------+
! fluxes_adv: calculates the fluxes for the advective part |
!----------------------------------------------------------+
subroutine fluxes_adv(ncells, ngcells, u, phi_left, phi_right, phi, flux)

	implicit none

	integer, intent(in) :: ncells, ngcells
	
	double precision, dimension(2*ngcells+ncells), intent(in) :: phi_left, phi_right, phi
	double precision, dimension(2*ngcells+ncells), intent(inout) :: flux
	
	double precision, intent(in) :: u
	
	integer :: i, imin, imax

	imin = ngcells + 1
	imax = ngcells + ncells

	! loop over all interfaces and calculate the linear advective flux.   	
	! the advection  velocity tells us which direction is upwind.
	if (u <= 0.d0) then 
		do i = imin, imax+1
			flux(i) = u*phi_left(i)
		end do
	else
		do i = imin, imax+1
			flux(i) = u*phi_right(i)
		end do

	end if
	
	return
end subroutine fluxes_adv


!---------------------------------+
! rhs_adv_timestep: rhs of adv eq |
!---------------------------------+
subroutine rhs_adv_timestep(ncells, ngcells, init, res, dt, dx, u, cn, recontype,	&
		   	limiter, update)

	implicit none

	integer, intent(in) :: ncells, ngcells, update, recontype, limiter
	
	double precision, dimension(2*ngcells +ncells), intent(inout) :: init, res
	double precision, intent(inout) :: dt
	double precision, intent(in)	:: dx, u, cn

	double precision, dimension(2*ngcells+ncells) :: phi_left, phi_right, flux
	
	integer :: i, imin, imax

	imin = ngcells + 1 
	imax = ngcells + ncells


	! compute next time step (if update == 1)
	if (update == 1) then
		call calc_dt(dx, u, cn, dt)
	end if	

	! calculates cell interfaces	
	call reconstruct(ncells, ngcells, dt, dx, u, recontype, limiter,			 & 
														init, phi_left, phi_right)
	
	! compute fluxes and timestep
	call fluxes_adv(ncells, ngcells, u, phi_left, phi_right, init, flux)

	do i = imin, imax 
		res(i) = (flux(i) - flux(i+1)) / dx
	end do

	return
end subroutine rhs_adv_timestep


!------------------------------------------------------------------+
! RK2: Runge-Kutta time integration (2nd-Order depending in Alpha) |
!------------------------------------------------------------------+
subroutine RK2(ncells, ngcell, phi, alpha, dt, dx, u, cn, recontype, limiter)
	
	implicit none

	integer, intent(in) :: ncells, ngcells
	integer, intent(in) :: recontype, limiter	

	double precision, intent(in) :: dt, dx, u, cn, alpha
	double precision, dimension(2*ngcells+ncells), intent(inout) :: phi 
 	
	double precision, dimension(2*ngcells+ncells) :: k_1, k_2_init, k_2
	
	imin = ngcells + 1
	imax = ngcells + ncells 

	call update_gcells(ncells, ngcells, phi)		
	call rhs_adv_timestep(ncells, ngcells, phi, k_1, dt, dx, u, cn, recontype,	&
																	   limiter, 1)

	if (t + dt > tmax) then
		dt = (tmax - t)
	end if

	k_2_init(imin:imax) = phi(imin:imax) + alpha*dt*k_1(imin:imax)
	
	call update_gcells(ncells, ngcells, k_2_init)
	call rhs_adv_timestep(ncells, ngcells, phi, k_2, dt, dx, u, cn, recontype, &
		     														   limiter, 0)

	phi(imin:imax) = phi(imin:imax) + dt*( (1.d0-1.d0/(2.d0*alpha))*k_1(imin:imax) &
										 	    +1.d0/(2.d0*alpha) *k_2(imin:imax) ) 
	return     
end subroutine RK2


!=================================================================================
! Functions
!=================================================================================

!---------------------------------------------------------------------------------
! Limiter Functions         
!---------------------------------------------------------------------------------

function minmod(a,b)
	
	implicit none

	double precision, intent(in)  :: a,b
	double precision, intent(out) :: minmod

	if (abs(a) < abs(b) .and. a*b > 0.d0) then
		minmod = a
	else if (abs(b) < abs(a) .and. a*b > 0.d0) then
		minmod = b
	else
		minmid = 0.d0
	endif

	return minmod

end function minmod


function maxmod(a,b)
 
    implicit none

    double precision, intent(in)  :: a,b
    double precision, intent(out) :: maxmod

    if (abs(a) > abs(b) .and. a*b > 0.d0) then
        maxmod = a
    else if (abs(b) > abs(a) .and. a*b > 0.d0) then
        maxmod = b
    else
        maxmid = 0.d0
    endif
 
    return maxmod
 
end function maxmod




