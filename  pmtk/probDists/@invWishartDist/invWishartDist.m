classdef invWishartDist < matrixDist
  
  properties
  end
  
  %% Main methods
  methods
    function m = invWishartDist(dof, Sigma)
      % We require Sigma is posdef and dof > d-1
      % (An alternative parameterization requires dof > 2d)
      if nargin == 0
        m.Sigma = [];
        return;
      end
      m.dof = dof;
      m.Sigma = Sigma; % scale maxtrix 
    end
    
    function objS = convertToScalarDist(obj)
      if ndims(obj) ~= 1, error('cannot convert to scalarDst'); end
      objS = invGammaDist(obj.dof/2, obj.Sigma/2);
     end
    
    function d = ndims(obj)
      d = size(obj.Sigma,1);
    end
    
    function lnZ = lognormconst(obj)
      d = ndims(obj);
      v = obj.dof;
      S = obj.Sigma;
      lnZ = (v*d/2)*log(2) + mvtGammaln(d,v/2) -(v/2)*logdet(S);
    end
    
    function m = mean(obj)
      m = obj.Sigma / (obj.dof - ndims(obj) - 1);
    end
    
    function m = mode(obj)
      m = obj.Sigma / (obj.dof + ndims(obj) + 1);
    end
 
    
    function L = logprob(obj, X)
      % L(i) = log p(X(:,:,i) | theta)
      % If object is scalar, then L(i) = log p(X(i) | theta))
      v = obj.dof;
      d = ndims(obj);
      if d==1
        n = length(X);
        X(find(X==0)) = eps;
        X = reshape(X,[1 1 n]);
      else
        n = size(X,3);
      end
      logZ = lognormconst(obj);
      for i=1:n
        L(i) = -(v+d+1)/2*logdet(X(:,:,i)) -0.5*trace(obj.Sigma*inv(X(:,:,i))) - logZ;
      end
      L = L(:);
    end
      
    function X = sample(obj, n)
      % X(:,:,i) is a random matrix drawn from IW() for i=1:n
      d = ndims(obj);
      if nargin < 2, n = 1; end
      X  = zeros(d,d,n);
      [X(:,:,1), DI] = iwishrnd(obj.Sigma, obj.dof);
      for i=2:n
        X(:,:,i) = iwishrnd(obj.Sigma, obj.dof, DI);
      end
    end
    
   
    function mm = marginal(obj, query)
      % If M ~ IW(dof,S), then M(q,q) ~ IW(dof-2d+2q, S(q,q))
      % Press (2005) p118
      q = length(query); d = ndims(obj); v = obj.dof;
      mm = invWishartDist(v-2*d+2*q, obj.Sigma(query,query));
    end
     
    
    
  end
  
  %% Demos
  methods(Static = true)
     function h = demoPlot2d()
      % plot some IW distributions
      seed=1;randn('state',seed);rand('state',seed);
      S=randpd(2);R=cov2cor(S)
      p=invWishartDist(20,S);
      mean(p)
      figure(1);clf;plotSamples2d(p,9);
      figure(2);clf;plotMarginals(p)
    end
    
     function h = demoPlot1d()
       % plot some invchi2 distributions
       figure;
       %nu = [1 1 1  5 5 5 ];
       nu = [1 1 1 2 2 2];
       sigma2 = [0.5 1 2  0.5 1 2];
       %sigma2 = sigma2 .* nu;
       N = length(nu);
       [styles, colors, symbols] =  plotColors;
       %colors = hsvrand(N);
       xrange =[0.01 2];
       for i=1:N
         h = plot(invWishartDist(nu(i), sigma2(i)), 'plotArgs', styles{i}, 'xrange',xrange);
         hold on
         str{i} = sprintf('%s %3.1f, %s %3.1f', '\nu', nu(i), '\sigma^2', sigma2(i));
       end
       legend(str);
       title(sprintf('IW(%s, %s)', '\nu', '\sigma^2'));
     end

  end
    
    
end