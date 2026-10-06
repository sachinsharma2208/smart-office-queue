INSERT INTO departments (name, code, sort_order) VALUES
    ('IT Support',     'IT',  1),
    ('HR',             'HR',  2),
    ('Accounts',       'ACC', 3),
    ('Administration', 'ADM', 4)
ON CONFLICT (code) DO NOTHING;
