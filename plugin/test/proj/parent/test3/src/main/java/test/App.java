package test;
import java.io.IOException;

/**
 * Hello world!
 *
 */
public class App extends Plunk implements Plonk {

    public static void main( String[] args ) {
        System.out.println( "Hello World!" );
        try {
            int key = 0;
            while(key != 122) {
                key = System.in.read();
                System.out.print(String.valueOf(key));
            }
        }
        catch(IOException ex) {
            ex.printStackTrace();
        }
    }

    public void doApp1() {
        int a = 0;
    }

    public void doPlonk() {
        int a = 0;
    }

    public void doPlunk() {
        int a = 0;
    }

}
