module stepon

use shr_kind_mod,   only: r8 => shr_kind_r8
use spmd_utils,     only: iam, mpicom
use ppgrid,         only: begchunk, endchunk

use physics_types,  only: physics_state, physics_tend
use dyn_comp,       only: dyn_import_t, dyn_export_t

use perf_mod,       only: t_startf, t_stopf, t_barrierf
use cam_abortutils, only: endrun

use parallel_mod,   only: par
use dimensions_mod, only: nelemd

implicit none
private
save

public stepon_init
public stepon_run1
public stepon_run2
public stepon_run3
public stepon_final

!=========================================================================================
contains
!=========================================================================================

subroutine stepon_init(dyn_in, dyn_out )

   use cam_history,    only: addfld, add_default, horiz_only
   use constituents,   only: pcnst, cnst_name, cnst_longname
   use dimensions_mod, only: fv_nphys, cnst_name_gll, cnst_longname_gll, qsize

   ! arguments
   type (dyn_import_t), intent(inout) :: dyn_in  ! Dynamics import container
   type (dyn_export_t), intent(inout) :: dyn_out ! Dynamics export container

   ! local variables
   integer :: m, m_cnst
   !----------------------------------------------------------------------------
   ! These fields on dynamics grid are output before the call to d_p_coupling.
   do m_cnst = 1, qsize
     call addfld(trim(cnst_name_gll(m_cnst))//'_gll',  (/ 'lev' /), 'I', 'kg/kg',   &
          trim(cnst_longname_gll(m_cnst)), gridname='GLL')
     call addfld(trim(cnst_name_gll(m_cnst))//'dp_gll',  (/ 'lev' /), 'I', 'kg/kg',   &
          trim(cnst_longname_gll(m_cnst))//'*dp', gridname='GLL')
   end do
   call addfld('U_gll'     ,(/ 'lev' /), 'I', 'm/s ','U wind on gll grid',gridname='GLL')
   call addfld('V_gll'     ,(/ 'lev' /), 'I', 'm/s ','V wind on gll grid',gridname='GLL')
   call addfld('T_gll'     ,(/ 'lev' /), 'I', 'K '  ,'T on gll grid'     ,gridname='GLL')
   call addfld('dp_ref_gll' ,(/ 'lev' /), 'I', '  '  ,'dp dry / dp_ref on gll grid'     ,gridname='GLL')
   call addfld('PSDRY_gll' ,horiz_only , 'I', 'Pa ' ,'psdry on gll grid' ,gridname='GLL')
   call addfld('PS_gll'    ,horiz_only , 'I', 'Pa ' ,'ps on gll grid'    ,gridname='GLL')
   call addfld('PHIS_gll'  ,horiz_only , 'I', 'Pa ' ,'PHIS on gll grid'  ,gridname='GLL')

   ! Fields for initial condition files
   call addfld('U&IC',   (/ 'lev' /),  'I', 'm/s', 'Zonal wind',     gridname='GLL' )
   call addfld('V&IC',   (/ 'lev' /),  'I', 'm/s', 'Meridional wind',gridname='GLL' )
   ! Don't need to register U&IC V&IC as vector components since we don't interpolate IC files
   call add_default('U&IC',0, 'I')
   call add_default('V&IC',0, 'I')

   call addfld('PS&IC', horiz_only,  'I', 'Pa', 'Surface pressure',       gridname='GLL')
   call addfld('T&IC',  (/ 'lev' /), 'I', 'K',  'Temperature',            gridname='GLL')
   call add_default('PS&IC', 0, 'I')
   call add_default('T&IC',  0, 'I')

   do m_cnst = 1,pcnst
      call addfld(trim(cnst_name(m_cnst))//'&IC', (/ 'lev' /), 'I', 'kg/kg', &
                  trim(cnst_longname(m_cnst)), gridname='GLL')
      call add_default(trim(cnst_name(m_cnst))//'&IC', 0, 'I')
   end do

end subroutine stepon_init

!=========================================================================================

subroutine stepon_run1( dtime_out, phys_state, phys_tend,               &
                        pbuf2d, dyn_in, dyn_out )

   use time_manager,   only: get_step_size
   use dp_coupling,    only: d_p_coupling
   use physics_buffer, only: physics_buffer_desc

   use time_mod,       only: tstep                    ! dynamics timestep

   real(r8),             intent(out)   :: dtime_out   ! Time-step
   type(physics_state),  intent(inout) :: phys_state(begchunk:endchunk)
   type(physics_tend),   intent(inout) :: phys_tend(begchunk:endchunk)
   type (dyn_import_t),  intent(inout) :: dyn_in  ! Dynamics import container
   type (dyn_export_t),  intent(inout) :: dyn_out ! Dynamics export container
   type (physics_buffer_desc), pointer :: pbuf2d(:,:)
   !----------------------------------------------------------------------------

   dtime_out = get_step_size()

   if (iam < par%nprocs) then
      if (tstep <= 0)      call endrun('stepon_run1: bad tstep')
      if (dtime_out <= 0)  call endrun('stepon_run1: bad dtime')

      ! write diagnostic fields on gll grid and initial file
      call diag_dynvar_ic(dyn_out%elem, dyn_out%fvm)
   end if

   call t_barrierf('sync_d_p_coupling', mpicom)
   call t_startf('d_p_coupling')
   ! Move data into phys_state structure.
   call d_p_coupling(phys_state, phys_tend,  pbuf2d, dyn_out )
   call t_stopf('d_p_coupling')

end subroutine stepon_run1

!=========================================================================================

subroutine stepon_run2(phys_state, phys_tend, dyn_in, dyn_out)

   use dp_coupling,            only: p_d_coupling
   use dyn_grid,               only: TimeLevel

   use time_mod,               only: TimeLevel_Qdp
   use control_mod,            only: qsplit
   use prim_advance_mod,       only: calc_tot_energy_dynamics


   ! arguments
   type(physics_state), intent(inout) :: phys_state(begchunk:endchunk)
   type(physics_tend),  intent(inout) :: phys_tend(begchunk:endchunk)
   type (dyn_import_t), intent(inout) :: dyn_in  ! Dynamics import container
   type (dyn_export_t), intent(inout) :: dyn_out ! Dynamics export container

   ! local variables
   integer :: tl_f, tl_fQdp
   !----------------------------------------------------------------------------

   tl_f = TimeLevel%n0   ! timelevel which was adjusted by physics
   call TimeLevel_Qdp(TimeLevel, qsplit, tl_fQdp)

   call t_barrierf('sync_p_d_coupling', mpicom)
   call t_startf('p_d_coupling')
   ! copy from phys structures -> dynamics structures
   call p_d_coupling(phys_state, phys_tend, dyn_in, tl_f, tl_fQdp)
   call t_stopf('p_d_coupling')

   if (iam < par%nprocs) then
      call calc_tot_energy_dynamics(dyn_in%elem,dyn_in%fvm, 1, nelemd, tl_f, tl_fQdp,'dED')
   end if

end subroutine stepon_run2

!=========================================================================================

subroutine stepon_run3(dtime, cam_out, phys_state, dyn_in, dyn_out)

   use camsrfexch,     only: cam_out_t
   use dyn_comp,       only: dyn_run
   use advect_tend,    only: compute_adv_tends_xyz
   use dyn_grid,       only: TimeLevel
   use time_mod,       only: TimeLevel_Qdp
   use control_mod,    only: qsplit   
   ! arguments
   real(r8),            intent(in)    :: dtime   ! Time-step
   type(cam_out_t),     intent(inout) :: cam_out(:) ! Output from CAM to surface
   type(physics_state), intent(inout) :: phys_state(begchunk:endchunk)
   type (dyn_import_t), intent(inout) :: dyn_in  ! Dynamics import container
   type (dyn_export_t), intent(inout) :: dyn_out ! Dynamics export container

   integer :: tl_f, tl_fQdp
   !--------------------------------------------------------------------------------------
   
   call t_startf('comp_adv_tends1')
   tl_f = TimeLevel%n0 
   call TimeLevel_Qdp(TimeLevel, qsplit, tl_fQdp)   
   call compute_adv_tends_xyz(dyn_in%elem,dyn_in%fvm,1,nelemd,tl_fQdp,tl_f)
   call t_stopf('comp_adv_tends1')
   
   call t_barrierf('sync_dyn_run', mpicom)
   call t_startf('dyn_run')
   call dyn_run(dyn_out)
   call t_stopf('dyn_run')

   call t_startf('comp_adv_tends2')
   tl_f = TimeLevel%n0 
   call TimeLevel_Qdp(TimeLevel, qsplit, tl_fQdp)   
   call compute_adv_tends_xyz(dyn_in%elem,dyn_in%fvm,1,nelemd,tl_fQdp,tl_f)
   call t_stopf('comp_adv_tends2')   

end subroutine stepon_run3

!=========================================================================================

subroutine stepon_final(dyn_in, dyn_out)

   type (dyn_import_t), intent(inout) :: dyn_in  ! Dynamics import container
   type (dyn_export_t), intent(inout) :: dyn_out ! Dynamics export container

end subroutine stepon_final

!=========================================================================================

subroutine diag_dynvar_ic(elem, fvm)
   use constituents,           only: cnst_type
   use cam_history,            only: write_inithist, outfld, hist_fld_active, fieldname_len
   use dyn_grid,               only: TimeLevel

   use time_mod,               only: TimeLevel_Qdp   !  dynamics typestep
   use control_mod,            only: qsplit
   use hybrid_mod,             only: config_thread_region, get_loop_ranges
   use hybrid_mod,             only: hybrid_t
   use dimensions_mod,         only: np, npsq, nc, nhc, fv_nphys, qsize, ntrac, nlev
   use dimensions_mod,         only: cnst_name_gll
   use constituents,           only: cnst_name
   use element_mod,            only: element_t
   use fvm_control_volume_mod, only: fvm_struct
   use fvm_mapping,            only: fvm2dyn
   use physconst,              only: get_sum_species, get_ps,thermodynamic_active_species_idx
   use physconst,              only: thermodynamic_active_species_idx_dycore,get_dp_ref
   use hycoef,                 only: hyai, hybi, ps0
   ! arguments
   type(element_t) , intent(in)    :: elem(1:nelemd)
   type(fvm_struct), intent(inout) :: fvm(:)

   ! local variables
   integer              :: ie, i, j, k, m, m_cnst, nq
   integer              :: tl_f, tl_qdp
   character(len=fieldname_len) :: tfname

   type(hybrid_t)        :: hybrid
   integer               :: nets, nete
   real(r8), allocatable :: ftmp(:,:,:)
   real(r8), allocatable :: fld_fvm(:,:,:,:,:), fld_gll(:,:,:,:,:)
   real(r8), allocatable :: fld_2d(:,:)
   logical,  allocatable :: llimiter(:)
   real(r8)              :: qtmp(np,np,nlev), dp_ref(np,np,nlev), ps_ref(np,np)
   real(r8), allocatable :: factor_array(:,:,:)
   !----------------------------------------------------------------------------

   tl_f = timelevel%n0
   call TimeLevel_Qdp(TimeLevel, qsplit, tl_Qdp)

   allocate(ftmp(npsq,nlev,2))

   ! Output tracer fields for analysis of advection schemes
   do m_cnst = 1, qsize
     tfname = trim(cnst_name_gll(m_cnst))//'_gll'
     if (hist_fld_active(tfname)) then
       do ie = 1, nelemd
         qtmp(:,:,:) =  elem(ie)%state%Qdp(:,:,:,m_cnst,tl_qdp)/&
              elem(ie)%state%dp3d(:,:,:,tl_f)
         do j = 1, np
           do i = 1, np
             ftmp(i+(j-1)*np,:,1) = elem(ie)%state%Qdp(i,j,:,m_cnst,tl_qdp)/&
                  elem(ie)%state%dp3d(i,j,:,tl_f)
           end do
         end do
         call outfld(tfname, ftmp(:,:,1), npsq, ie)
       end do
     end if
   end do

   do m_cnst = 1, qsize
     tfname = trim(cnst_name_gll(m_cnst))//'dp_gll'
     if (hist_fld_active(tfname)) then
       do ie = 1, nelemd
         do j = 1, np
           do i = 1, np
             ftmp(i+(j-1)*np,:,1) = elem(ie)%state%Qdp(i,j,:,m_cnst,tl_qdp)
           end do
         end do
         call outfld(tfname, ftmp(:,:,1), npsq, ie)
       end do
     end if
    end do

   if (hist_fld_active('U_gll') .or. hist_fld_active('V_gll')) then
      do ie = 1, nelemd
         do j = 1, np
            do i = 1, np
               ftmp(i+(j-1)*np,:,1) = elem(ie)%state%v(i,j,1,:,tl_f)
               ftmp(i+(j-1)*np,:,2) = elem(ie)%state%v(i,j,2,:,tl_f)
            end do
         end do
         call outfld('U_gll', ftmp(:,:,1), npsq, ie)
         call outfld('V_gll', ftmp(:,:,2), npsq, ie)
      end do
   end if

   if (hist_fld_active('T_gll')) then
      do ie = 1, nelemd
         do j = 1, np
            do i = 1, np
               ftmp(i+(j-1)*np,:,1) = elem(ie)%state%T(i,j,:,tl_f)
            end do
         end do
         call outfld('T_gll', ftmp(:,:,1), npsq, ie)
      end do
   end if

   if (hist_fld_active('dp_ref_gll')) then
     do ie = 1, nelemd       
       call get_dp_ref(hyai,hybi,ps0,1,np,1,np,1,nlev,elem(ie)%state%phis(:,:),dp_ref(:,:,:),ps_ref(:,:))
         do j = 1, np
            do i = 1, np
               ftmp(i+(j-1)*np,:,1) = elem(ie)%state%dp3d(i,j,:,tl_f)/dp_ref(i,j,:)
            end do
         end do
         call outfld('dp_ref_gll', ftmp(:,:,1), npsq, ie)
      end do
   end if

   if (hist_fld_active('PSDRY_gll')) then
      do ie = 1, nelemd
         do j = 1, np
            do i = 1, np
               ftmp(i+(j-1)*np,1,1) = elem(ie)%state%psdry(i,j)
            end do
         end do
         call outfld('PSDRY_gll', ftmp(:,1,1), npsq, ie)
      end do
   end if

   if (hist_fld_active('PS_gll')) then
     allocate(fld_2d(np,np))
     do ie = 1, nelemd
       call get_ps(1,np,1,np,1,nlev,qsize,elem(ie)%state%Qdp(:,:,:,:,tl_Qdp),&
            thermodynamic_active_species_idx_dycore,elem(ie)%state%dp3d(:,:,:,tl_f),fld_2d,hyai(1)*ps0)
         do j = 1, np
            do i = 1, np
              ftmp(i+(j-1)*np,1,1) = fld_2d(i,j)
            end do
         end do
         call outfld('PS_gll', ftmp(:,1,1), npsq, ie)
       end do
       deallocate(fld_2d)
   end if

   if (hist_fld_active('PHIS_gll')) then
      do ie = 1, nelemd
         call outfld('PHIS_gll', RESHAPE(elem(ie)%state%phis, (/np*np/)), np*np, ie)
      end do
   end if

   if (write_inithist()) then
     allocate(fld_2d(np,np))     
     do ie = 1, nelemd
       call get_ps(1,np,1,np,1,nlev,qsize,elem(ie)%state%Qdp(:,:,:,:,tl_Qdp),&
            thermodynamic_active_species_idx_dycore,elem(ie)%state%dp3d(:,:,:,tl_f),fld_2d,hyai(1)*ps0)       
       do j = 1, np
         do i = 1, np
           ftmp(i+(j-1)*np,1,1) = fld_2d(i,j)
         end do
       end do
       call outfld('PS&IC', ftmp(:,1,1), npsq, ie)       
     end do
     deallocate(fld_2d)
      if (fv_nphys < 1) allocate(factor_array(np,np,nlev))

      do ie = 1, nelemd
         call outfld('T&IC', RESHAPE(elem(ie)%state%T(:,:,:,tl_f),   (/npsq,nlev/)), npsq, ie)
         call outfld('U&IC', RESHAPE(elem(ie)%state%v(:,:,1,:,tl_f), (/npsq,nlev/)), npsq, ie)
         call outfld('V&IC', RESHAPE(elem(ie)%state%v(:,:,2,:,tl_f), (/npsq,nlev/)), npsq, ie)

         if (fv_nphys < 1) then
            call get_sum_species(1,np,1,np,1,nlev,qsize,elem(ie)%state%Qdp(:,:,:,:,tl_qdp), &
               thermodynamic_active_species_idx_dycore, factor_array,dp_dry=elem(ie)%state%dp3d(:,:,:,tl_f))
            factor_array(:,:,:) = 1.0_r8/factor_array(:,:,:)
            do m_cnst = 1, qsize
               if (cnst_type(m_cnst) == 'wet') then
                  call outfld(trim(cnst_name(m_cnst))//'&IC', &
                       RESHAPE(factor_array(:,:,:)*elem(ie)%state%Qdp(:,:,:,m_cnst,tl_qdp)/&
                       elem(ie)%state%dp3d(:,:,:,tl_f), (/npsq,nlev/)), npsq, ie)
               else
                  call outfld(trim(cnst_name(m_cnst))//'&IC', &
                       RESHAPE(elem(ie)%state%Qdp(:,:,:,m_cnst,tl_qdp)/&
                       elem(ie)%state%dp3d(:,:,:,tl_f), (/npsq,nlev/)), npsq, ie)
               end if
            end do
         end if
      end do

      if (fv_nphys > 0) then
         !JMD $OMP PARALLEL NUM_THREADS(horz_num_threads), DEFAULT(SHARED), PRIVATE(hybrid,nets,nete,n)
         !JMD        hybrid = config_thread_region(par,'horizontal')
         hybrid = config_thread_region(par,'serial')
         call get_loop_ranges(hybrid, ibeg=nets, iend=nete)

         allocate(fld_fvm(1-nhc:nc+nhc,1-nhc:nc+nhc,nlev,ntrac,nets:nete))
         allocate(fld_gll(np,np,nlev,ntrac,nets:nete))
         allocate(llimiter(ntrac))
         allocate(factor_array(nc,nc,nlev))
         llimiter = .true.
         do ie = nets, nete
           call get_sum_species(1,nc,1,nc,1,nlev,ntrac,fvm(ie)%c(1:nc,1:nc,:,:),thermodynamic_active_species_idx,factor_array)
           factor_array(:,:,:) = 1.0_r8/factor_array(:,:,:)
           do m_cnst = 1, ntrac
             if (cnst_type(m_cnst) == 'wet') then
               fld_fvm(1:nc,1:nc,:,m_cnst,ie) = fvm(ie)%c(1:nc,1:nc,:,m_cnst)*factor_array(:,:,:)
             else
               fld_fvm(1:nc,1:nc,:,m_cnst,ie) = fvm(ie)%c(1:nc,1:nc,:,m_cnst)
             end if
           end do
         end do

         call fvm2dyn(fld_fvm, fld_gll, hybrid, nets, nete, nlev, ntrac, fvm(nets:nete), llimiter)

         do ie = nets, nete
            do m_cnst = 1, ntrac
               call outfld(trim(cnst_name(m_cnst))//'&IC', &
                    RESHAPE(fld_gll(:,:,:,m_cnst,ie), (/npsq,nlev/)), npsq, ie)
            end do
         end do

         deallocate(fld_fvm)
         deallocate(fld_gll)
         deallocate(llimiter)
      end if
      deallocate(factor_array)
   end if  ! if (write_inithist)

   deallocate(ftmp)

end subroutine diag_dynvar_ic

!=========================================================================================

end module stepon
