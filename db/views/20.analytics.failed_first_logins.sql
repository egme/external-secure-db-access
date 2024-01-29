select
     k.id,
     u.email,
     k.created_at as keyphrase_created_at,
     l.created_at as login_attemp_at,
     l.success as login_attempt_result
from 
     analytics.users_with_fresh_keyphrases as k,
     public.users as u,
     login_attempts as l
where
     k.id = u.id::varchar and
     k.id = l.user_id::varchar and
     l.created_at >= k.created_at

