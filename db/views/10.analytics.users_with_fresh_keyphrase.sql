select 
     u.id::varchar,
     u.email,
     k.created_at
from 
     public.users as u,
     public.secret_keyphrases as k
where
     u.id = k.user_id and
     k.created_at > NOW() - INTERVAL '5 minutes'
