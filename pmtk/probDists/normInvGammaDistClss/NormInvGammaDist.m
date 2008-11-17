classdef NormInvGammaDist < VecDist
  % p(m,s2|params) = N(m|mu, s2 / k0 ) IG(s2| a,b)
  properties
    mu;
    k;
    a;
    b;
  end

  %% main methods
  methods
    function m = NormInvGammaDist(varargin)
      if nargin == 0, varargin = {}; end
      [mu, k, a, b] = process_options(...
        varargin, 'mu', [], 'k', [], 'a', [], 'b', []);
      m.mu = mu; m.k = k; m.a = a; m.b = b;
    end
    
 
    function mm = marginal(obj, queryVar)
      % marginal(obj, 'sigma') or marginal(obj, 'mu')
      switch lower(queryVar)
        case 'sigma'
          mm = InvGammaDist(obj.a, obj.b);
        case 'mu'
          mm = StudentDist(2*obj.a, obj.mu, obj.b/(obj.a * obj.k));
        otherwise
          error(['unrecognized variable ' queryVar])
      end
    end
    
    function logZ = lognormconst(obj)
      logZ = 0.5*log(2*pi) -0.5*log(obj.k) + gammaln(obj.a) -obj.a*log(obj.b);
    end
    
    function L = logprob(obj, X)
       % L(i) = log p(X(i,:) | theta), where X(i,:) = [mu sigma]
      n = size(X,1);
      sigma2 = X(:,2); mu = X(:,1);
      a = obj.a; b = obj.b; m = obj.mu; k = obj.k;
      L = -(a+3/2)*log(sigma2) - (2*b + k*(m-mu).^2)./(2*sigma2);
      L = L - lognormconst(obj)*ones(n,1);
      %{
      for i=1:n
        pgauss = GaussDist(obj.mu, X(i,2)./obj.k);
        pig = InvGammaDist(obj.a, obj.b);
        L2(i) = logprob(pgauss, X(i,1)) + logprob(pig, X(i,2));
      end
      assert(approxeq(L,L2))
      %}
    end
      
  function xrange = plotRange(obj)
      d = length(obj.mu);
      if d > 1, error('not supported'); end
      sf = 2;
      S = obj.b/obj.a;
      xrange = [obj.mu-sf*S, obj.mu+sf*S, 0.01, sf*S];
    end
  end
    
  %% demos
  methods(Static = true)
  end
    
end