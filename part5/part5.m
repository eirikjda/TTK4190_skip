% Project in TTK4190 Guidance and Control of Vehicles 
%
% Author:           My name
% Study program:    My study program

clear all;
close all;
load('WP.mat')
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% USER INPUTS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
h  = 0.1;    % sampling time [s]
Ns = 87000;  % no. of samples

%psi_ref = 10 * pi/180;  % desired yaw angle (rad)
%U_d = 7;                % desired cruise speed (m/s)
U_d = 7;                % desired cruise speed (m/s)
               
% ship parameters 
m = 17.0677e6;          % mass (kg)
Iz = 2.1732e10;         % yaw moment of inertia about CO (kg m^3)
xg = -3.7;              % CG x-ccordinate (m)
L = 161;                % length (m)
B = 21.8;               % beam (m)
T = 8.9;                % draft (m)
KT = 0.7;               % propeller coefficient (-)
Dia = 3.3;              % propeller diameter (m)
rho = 1025;             % density of water (kg/m^3)
visc = 1e-6;            % kinematic viscousity at 20 degrees (m/s^2)
eps = 0.001;            % a small number added to ensure that the denominator of Cf is well defined at u=0
k = 0.1;                % form factor giving a viscous correction
t_thr = 0.05;           % thrust deduction number

% rudder limitations
delta_max  = 40 * pi/180;        % max rudder angle      (rad)
Ddelta_max = 5  * pi/180;        % max rudder derivative (rad/s)

% added mass matrix about CO
Xudot = -8.9830e5;
Yvdot = -5.1996e6;
Yrdot =  9.3677e5;
Nvdot =  Yrdot;
Nrdot = -2.4283e10;
MA = -[ Xudot 0    0 
        0 Yvdot Yrdot
        0 Nvdot Nrdot ];
MA_lin = MA(2:3,2:3);

% rigid-body mass matrix
MRB = [ m 0    0 
        0 m    m*xg
        0 m*xg Iz ];
MRB_lin = MRB(2:3,2:3);
    
Minv = inv(MRB + MA); % Added mass is included to give the total inertia
Minv_lin = inv(MRB_lin + MA_lin);

% ocean current in NED
Vc = 1;                             % current speed (m/s)
betaVc = deg2rad(45);               % current direction (rad)

% wind expressed in NED
Vw = 10;                   % wind speed (m/s)
betaVw = deg2rad(135);     % wind direction (rad)
rho_a = 1.247;             % air density at 10 deg celsius
cy = 0.95;                 % wind coefficient in sway
cn = 0.15;                 % wind coefficient in yaw
A_Lw = 10 * L;             % projected lateral area

%?w=???Vw??
% linear damping matrix (only valid for zero speed)
T1 = 20; T2 = 20; T6 = 10;

Xu = -(m - Xudot) / T1;
Yv = -(m - Yvdot) / T2;
Nr = -(Iz - Nrdot)/ T6;
D = diag([-Xu -Yv -Nr]);         % zero speed linear damping
D_lin = D(2:3,2:3);

%Linearized coriolis matrices
CRB_lin = [ 0 0 0 
    0  0  m*U_d
    0 0  m*xg*U_d];
CRB_lin = CRB_lin(2:3,2:3);
% coriolis due to added mass
CA_lin = [  0   0   0
        0   0   -Xudot*U_d 
      0    (Xudot-Yvdot)*U_d -Yrdot*U_d];
CA_lin = CA_lin(2:3,2:3);

% rudder coefficients (Section 9.5)
b = 2;
AR = 8;
CB = 0.8;

lambda = b^2 / AR;
tR = 0.45 - 0.28*CB;
CN = 6.13*lambda / (lambda + 2.25);
aH = 0.75;
xH = -0.4 * L;
xR = -0.5 * L;

X_delta2 = 0.5 * (1 - tR) * rho * AR * CN;
Y_delta = 0.25 * (1 + aH) * rho * AR * CN; 
N_delta = 0.25 * (xR + aH*xH) * rho * AR * CN;   

% input matrix
Bu = @(u_r,delta) [ (1-t_thr)  -u_r^2 * X_delta2 * delta
                        0      -u_r^2 * Y_delta
                        0      -u_r^2 * N_delta            ];

% linearized sway-yaw model (see (7.15)-(7.19) in Fossen (2021)) used
% for controller design. The code below should be modified.
N_lin = CRB_lin + CA_lin + D_lin;
b_lin = [-2*U_d*Y_delta -2*U_d*N_delta]';
%2c: tf
[NUM,DEN] = ss2tf(-Minv_lin*N_lin,Minv_lin*b_lin,[0 1],0);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%                    
% Heading Controller
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% rudder control law
wb = 0.06;
zeta = 1;
wn = 1 / sqrt( 1 - 2*zeta^2 + sqrt( 4*zeta^4 - 4*zeta^2 + 2) ) * wb;
K_nomoto = NUM(3)/DEN(3);
T_nomoto = DEN(2)/DEN(3) - NUM(2)/(K_nomoto*DEN(3));%168.2;
m_reg = T_nomoto/K_nomoto;
d_reg = 1/K_nomoto;
Kp = m_reg*wn^2;
Kd = 2*zeta*wn*m_reg;
Ki = wn/10*Kp;

% initial states
eta = [0 0 0]';
nu  = [0.1 0 0]';
delta = 0;
wn_ref = 0.03;
n = 0;
xd = [0 0 0]';
cum_error = 0;

%% Part 3
Ja = 0;
PD = 1.5;
AEAO = 0.65;
z = 4;
[KT,KQ] = wageningen(Ja,PD,AEAO,z);

Qm = 0;

t_T = 0.05;
%% part 4
cur_wp = [WP(1,1), WP(2,1)]; 
next_wp = [WP(1,2), WP(2,2)]; 
last_wp = cur_wp;
tell = 1;
%% part 5

x0 = [0 0 0]'; x_prd = x0; % initialization
P0 = eye(3);
P_prd = P0;
Qd = diag([1 1]); % covariance matrices
Rd = 1;
A = [ 0 1 0
    0 -1/T_nomoto -K_nomoto/T_nomoto
    0 0 0 ];
B = [0 K_nomoto/T_nomoto 0]';
C = [1 0 0];
E = [0 0; 1 0; 0 1];

Adk = eye(3) + h * A; Bdk = h * B; % discrete-time KF model
Cdk = C; Edk = h * E;

disp(rank(obsv(A,C)))



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MAIN LOOP
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
simdata = zeros(Ns+1,21);                % table of simulation data
wn_ref = 0.05;
noise_heading = normrnd(0,deg2rad(0.5),1,Ns+1);
noise_yaw_rate = normrnd(0,deg2rad(0.1),1,Ns+1);
for i=1:Ns+1
    eta(3) = wrapTo2Pi(eta(3));
    yaw_copy = eta(3);
    eta(3) = eta(3) + noise_heading(i);
    yaw_rate_copy = nu(3);
    nu(3) = nu(3) + noise_yaw_rate(i);
    yaw_noise = eta(3) + noise_heading(i);
    yaw_rate_noise = nu(3) + noise_yaw_rate(i);
    
    K = P_prd * Cdk'/( Cdk * P_prd * Cdk' + Rd ); % inv (cda�dkfj)
    IKC = eye(3) - K * Cdk;
    % Control input and measurement: u[k] and y[k]
    u = delta; % control system
    y = eta(3);
    % Corrector: x_hat[k] and P_hat[k]
    x_hat = x_prd + K * ssa( y - Cdk * x_prd ); % ssa modification
    P_hat = IKC * P_prd * IKC' + K * Rd * K';
    % Predictor: x_prd[k+1] and P_prd[k+1]
    x_prd = Adk * x_hat + Bdk * u;
    P_prd = Adk * P_hat * Adk' + Edk * Qd * Edk';
    
    %add estimated states
    eta(3) = x_hat(1);
    nu(3) = x_hat(2);
    delta = delta - x_hat(3);
    % Ship-wave simulator: x[k+1]

    if(sqrt((eta(1)-next_wp(1))^2+(eta(2)-next_wp(2))^2)<2.4*L) 
        last_wp = next_wp;
        tell = tell + 1;
        if (tell > 6)
            disp(i)
        else
        next_wp = [WP(1,tell), WP(2,tell)];
        disp('byttet')
        end
    end
    
    psi_ref = guidance(next_wp(1), next_wp(2), last_wp(1), last_wp(2), eta(1), eta(2), L,nu(1),nu(2));
    %psi_ref = deg2rad(-150);
    
    Ad = [ 0 1 0
           0 0 1
           -wn_ref^3  -3*wn_ref^2  -3*wn_ref ];
    Bd = [ 0 0 wn_ref^3 ]';
    xd_dot = Ad * xd + Bd * psi_ref;    
    t = (i-1) * h;                      % time (s)
    R = Rzyx(0,0,eta(3));
    
    % current (should be added here)
    nu_r = nu - [Vc*cos(betaVc), Vc*sin(betaVc), 0]' ;
    u_c = Vc*cos(betaVc);
  
    
    gamma_w = eta(3)-betaVw-pi;
    C_Y = cy*sin(gamma_w);
    C_N = cn*sin(2*gamma_w);
    

    
    % wind (should be added here)
    if t > 200
        Ywind = 1/2*rho_a*Vw^2*C_Y*A_Lw; % expression for wind moment in sway should be added.
        Nwind = 1/2*rho_a*Vw^2*C_N*A_Lw*L; % expression for wind moment in yaw should be added.
    else
        Ywind = 0;
        Nwind = 0;
    end
    tau_env = [0 Ywind Nwind]';
    
    % state-dependent time-varying matrices
    CRB = m * nu(3) * [ 0 -1 -xg 
                        1  0  0 
                        xg 0  0  ];
                    
    % coriolis due to added mass
    CA = [  0   0   Yvdot * nu_r(2) + Yrdot * nu_r(3)
            0   0   -Xudot * nu_r(1) 
          -Yvdot * nu_r(2) - Yrdot * nu_r(3)    Xudot * nu_r(1)   0];
    N = CRB + CA + D;
    
    % nonlinear surge damping
    Rn = L/visc * abs(nu_r(1));
    Cf = 0.075 / ( (log(Rn) - 2)^2 + eps);
    Xns = -0.5 * rho * (B*L) * (1 + k) * Cf * abs(nu_r(1)) * nu_r(1);
    
    % cross-flow drag
    Ycf = 0;
    Ncf = 0;
    dx = L/10;
    Cd_2D = Hoerner(B,T);
    for xL = -L/2:dx:L/2
        vr = nu_r(2);
        r = nu_r(3);
        Ucf = abs(vr + xL * r) * (vr + xL * r);
        Ycf = Ycf - 0.5 * rho * T * Cd_2D * Ucf * dx;
        Ncf = Ncf - 0.5 * rho * T * Cd_2D * xL * Ucf * dx;
    end
    d = -[Xns Ycf Ncf]';
    
    % reference models
    psi_d = xd(1);
    r_d = xd(2);
    u_d = U_d;
   
    % thrust 
    thr = rho * Dia^4 * KT * abs(n) * n;    % thrust command (N)

    % control law
    delta_c = -(Kp*(eta(3)-xd(1)) + Ki*cum_error +  Kd*(nu(3)-xd(2)) ) ;              % rudder angle command (rad)
    
    % ship dynamics
    u = [ thr delta ]';
    tau = Bu(nu_r(1),delta) * u;
    nu_dot = Minv * (tau_env + tau - N * nu_r - d); 
    eta_dot = R * nu;    
    
    % Rudder saturation and dynamics (Sections 9.5.2)
    if abs(delta_c) >= delta_max
        cum_error = cum_error - (h / Ki) * (sign(delta_c)*delta_max - delta_c);
        delta_c = sign(delta_c)*delta_max;
    end
    
    delta_dot = delta_c - delta;
    if abs(delta_dot) >= Ddelta_max
        delta_dot = sign(delta_dot)*Ddelta_max;
    end    
    
    
    
    % propeller dynamics
    Im = 100000; Tm = 10; Km = 0.6;         % propulsion parameters
    %Hs = Km / (Tm*s+1);
    n_c = 10;                               % propeller speed (rps)
    
    %prop control
    T_prop = rho *Dia^4*KT*n*abs(n);
    Q = rho *Dia^5*KQ*n*abs(n);
    T_d = (U_d-u_c)*Xu / (t_T-1); % t = i?
    n_d = sign(T_d)*sqrt(abs(T_d) / (rho*Dia^4*KT));
    Q_d = rho *Dia^5*KQ*n_d*abs(n_d);
    y = Q_d/Km;
    Qm_dot = 1/Tm*(-Qm+y*Km);
    Q_f = 0;
    
    n_dot = (1/Im) * (Qm - Q -Q_f);        % should be changed in Part 3
    % store simulation data in a table (for testing)
    simdata(i,:) = [t n_c delta_c n delta eta' nu' u_d psi_d r_d nu_r' yaw_copy yaw_rate_copy yaw_noise yaw_rate_noise];       
     
    % Euler integration
    eta = euler2(eta_dot,eta,h);
    nu  = euler2(nu_dot,nu,h);
    delta = euler2(delta_dot,delta,h);   
    n  = euler2(n_dot,n,h);
    cum_error = euler2(eta(3)-xd(1),cum_error,h);
    xd = euler2(xd_dot,xd,h);
    Qm = euler2(Qm_dot,Qm,h);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PLOTS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t       = simdata(:,1);                 % s
n_c     = 60 * simdata(:,2);            % rpm
delta_c = (180/pi) * simdata(:,3);      % deg
n       = 60 * simdata(:,4);            % rpm
delta   = (180/pi) * simdata(:,5);      % deg
x       = simdata(:,6);                 % m
y       = simdata(:,7);                 % m
psi     = (180/pi) * simdata(:,8);      % deg
u       = simdata(:,9);                 % m/s
v       = simdata(:,10);                % m/s
r       = (180/pi) * simdata(:,11);     % deg/s
u_d     = simdata(:,12);                % m/s
psi_d   = (180/pi) * simdata(:,13);     % deg
r_d     = (180/pi) * simdata(:,14);     % deg/s
nu_r    = [simdata(:,15) simdata(:,16) simdata(:,17)];
yaw_copy = (180/pi)*simdata(:,18);
yaw_rate_copy = (180/pi)*simdata(:,19);
yaw_noise = (180/pi)*simdata(:,20);
yaw_rate_noise = (180/pi)*simdata(:,21);

figure(69)
figure(gcf)
subplot(211)
plot(t,yaw_noise,t,yaw_copy,'linewidth',2); grid on;
legend('measured psi', 'real psi');
subplot(212)
plot(t,yaw_rate_noise,t,yaw_rate_copy,'linewidth',2); grid on;
legend(' measured r', ' real r');
title('measured vs real yaw and rate'); xlabel('time (s)');





figure(33)
figure(gcf)
siz=size(WP);
hold on
for ii=1:(siz(2)-1)   
plot([WP(2,ii), WP(2,ii+1)], [WP(1,ii), WP(1,ii+1)], 'r-x')
end
plot(y,x,'linewidth',2); axis('equal'); grid on;
title('North-East positions (m)');


% figure(1)
% figure(gcf)
% subplot(311)
% plot(y,x,'linewidth',2); axis('equal'); grid on
% title('North-East positions (m)'); xlabel('time (s)'); 
% subplot(312)
% plot(t,psi,t,psi_d,'linewidth',2); grid on;
% title('Actual and desired yaw angles (deg)'); xlabel('time (s)');
% legend('yaw', 'desired yaw');
% 
% subplot(313)
% plot(t,r,t,r_d,'linewidth',2); grid on;
% title('Actual and desired yaw rates (deg/s)'); xlabel('time (s)');
% legend('r', 'desired r');
% 
% figure(2)
% figure(gcf)
% subplot(311)
% plot(t,u,t,u_d,'linewidth',2); grid on;
% title('Actual and desired surge velocities (m/s)'); xlabel('time (s)');
% subplot(312)
% plot(t,n,t,n_c,'linewidth',2); grid on;
% title('Actual and commanded propeller speed (rpm)'); xlabel('time (s)');
% subplot(313)
% plot(t,delta,t,delta_c,'linewidth',2); grid on;
% title('Actual and commanded rudder angles (deg)'); xlabel('time (s)');

% figure(3) 
% figure(gcf)
% subplot(211)
% plot(t,u,'linewidth',2);
% title('Actual surge velocity (m/s)'); xlabel('time (s)');
% subplot(212)
% plot(t,v,'linewidth',2);
% title('Actual sway velocity (m/s)'); xlabel('time (s)');
% 
% U_r = zeros(Ns+1,1);
% disp(size(U_r))
% for i=1:Ns+1
%     U_r(i,1)= sqrt(nu_r(i,2)^2 + nu_r(i,1)^2);
% end
% U = zeros(Ns+1,1);
% for i=1:Ns+1
%     U(i,1)= sqrt(u(i)^2+v(i)^2);
% end
% betaC = zeros(Ns+1,1);
% chi = zeros(Ns+1,1);
% for i = 1:Ns+1
%     betaC(i) = rad2deg((atan(v(i)/u(i))));
%     chi(i) = betaC(i) + psi(i);
% end
% beta = zeros(Ns+1,1);
% for i = 1:Ns+1
%     beta(i) = rad2deg(asin(nu_r(i,2)/U_r(i)));
% end
% figure(4)
% figure(gcf)
% plot(t, beta, 'linewidth',2);grid on; hold on
% plot(t, betaC, 'linewidth',2);
% legend('sideslip','crabbie');
% title('sidelsipcrab');
% 
% figure(5)
% figure(gcf)
% plot(t, psi_d,t,psi,t,chi,'linewidth',2); grid on;
% legend('chi_d','psi','chi');
% title('2b')
% % 

%%
% %�ving3 
% Ja = 0;
% PD = 1.5;
% AEAO = 0.65;
% z = 4;
% [KT,KQ] = wageningen(Ja,PD,AEAO,z);
% 
% D_prop = 5;
% 
% T_prop = rho *D_prop^4*KT*n*abs(n);
% Q_prop = rho *D_prop^4*KQ*n*abs(n);
% 

%% part 5.del 2
x0 = [0 0 0]'; x_prd = x0; % initialization
P0 = eye(3);
P_prd = P0;
Qd = diag([1 1 1]); % covariance matrices
Rd = 1;
A = [ 0 1 0
    0 -1/T_nomoto -K_nomoto/T_nomoto
    0 0 0 ];
B = [0 K_nomoto/T_nomoto 0]';
C = [1 0 0];
E = [0 0; 1 0; 0 1];

Ad = eye(3) + h * A; Bd = h * B; % discrete-time KF model
Cd = C; Ed = h * E;

disp(rank(obsv(A,C)))