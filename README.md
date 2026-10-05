Opción A, por GitHub (la del Pull Request, recomendada):

Entra a github.com/neylar-11/NullPointers.
Pestaña Pull requests → New pull request.
base: main ← compare: feature/CU-03-actividad.
Create pull request → le pones título → Create pull request otra vez.
En esa misma página aparece el botón verde Merge pull request → Confirm merge.

Listo, ya está en main.

Opción B, desde la terminal (más rápida, sin revisión):

bash
git checkout main
git merge feature/CU-03-actividad
git push
git checkout feature/CU-03-actividad
